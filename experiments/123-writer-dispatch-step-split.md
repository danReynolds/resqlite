# Experiment 123: Writer Dispatch / Native Wall Split

**Date:** 2026-05-04
**Status:** In Review
**Direction:** `measurement-system`, `stream-rerun-dispatch`, `parameter-encoding-and-binding`

## Problem

After [exp 120](120-flush-admit-bound.md) and [exp 122](122-concrete-reader-pool-stream-admission.md)
drove the dispatcher park / wake-retry counters to zero on every measured stream
workload, the future-notes from those experiments named three remaining
candidates for stream-fanout latency: completion-side microtask churn, invalidation
traversal, and writer-side dispatch wall. [Exp 121](121-invalidation-traversal-audit.md)
ruled out invalidation traversal at the per-benchmark decision-threshold edge.
That leaves writer-side dispatch wall, which `signals.json` listed under
**both** `stream-rerun-dispatch.blockedOnMeasurement` ("writer-isolate wall vs
SQLite step wall split for overlap workloads") and
`parameter-encoding-and-binding.blockedOnMeasurement` ("writer-isolate profile
separating bind work from dispatch and step time"). Until that split exists,
implementation experiments in either direction are gated on the question:

> When a write request lands in the writer isolate, what fraction of its wall
> is the FFI write call itself vs the surrounding Dart-side dispatch (parameter
> encoding, dirty-table extraction, reply marshalling)?

The dispatcher counters from exp 115 don't answer it — they instrument the
reader-pool admission path, not the writer.

## Hypothesis

A profile-mode wall split inside the writer isolate, snapshotted to the main
isolate via a dedicated request type, will let any future writer-area
implementation experiment be gated on direct evidence rather than wall-time
delta alone — closing the same evaluation-gap pattern that exps 115 / 119 / 121
solved for the read side. The split itself is not an optimization; it is the
measurement future runners need before optimizing.

## Approach

Built three things in one commit:

1. **Per-write timing instrumentation in the writer isolate.** Added two
   counters to `ProfileCounters`:
   - `writerHandlerUs` / `writerHandlerCount` — cumulative wall inside
     `_handleExecute` + `_handleBatch` bodies, message receive through reply
     send.
   - `writerNativeUs` / `writerNativeCount` — cumulative wall specifically
     inside the FFI write call (`resqliteExecute`, `resqliteRunBatch`,
     `resqliteRunBatchNested`).

   Wired through optional `Stopwatch? nativeStopwatch` parameters on the three
   bindings so the timed region is exactly the FFI call and the surrounding
   `try`/`finally` blocks stay outside. All instrumentation is gated behind
   `kProfileMode` so release builds tree-shake to zero.

2. **Cross-isolate snapshot.** New `WriterProfileSnapshotRequest` /
   `WriterProfileSnapshotResponse` pair the writer's reply-port protocol
   already uses for everything else, plus a `Database.writerProfileSnapshot()`
   method that returns the four counter values as plain ints. Optional
   `reset: true` clears the writer's counters atomically with the snapshot,
   so the next call begins from a known baseline.

3. **Audit harness.** `benchmark/profile/writer_dispatch_split_audit.dart`
   runs five scenarios that mirror the workloads exp 119 / 121 already use,
   so the wall numbers and fractions are directly comparable across audits:

   - **A11c baseline** — 500 single-row UPDATEs, no streams. Isolates
     writer dispatch from any stream-engine work.
   - **A11c disjoint** — same writes, 50 streams projecting `id, a, b`,
     write to column `c` (column-elided by exp 106).
   - **A11c overlap** — same shape, write to column `a` (full reactive
     fanout).
   - **Keyed PK** — 50 PK-watching streams, 200 deterministic random
     writes (the keyed miss-path workload).
   - **Wide batch insert** — one `executeBatch` of 10,000 rows × 20 mixed
     TEXT/INTEGER/REAL params, mirroring the release wide-batch shape exp
     116 promoted.

   Each scenario resets both main- and writer-isolate counters before the
   stopwatch starts, takes the snapshots immediately after the stopwatch
   stops, and runs any emission drain *after* the snapshot so the
   `writerProfileSnapshot()` round-trip wall is not double-counted into
   the denominator. Wall convention matches exp 119 / 121: stopwatch
   stops on the last write.

## Results

Aggregate from `benchmark/profile/results/exp-123-writer-dispatch-split-aggregate.md`,
plus run-to-run spread across three repeated runs (single-machine, Apple
Silicon, reader pool size 4):

| workload | wall_ms range | writer_handler / wall | native / handler | dispatch overhead / wall |
|---|---:|---:|---:|---:|
| A11c baseline (500 single writes, no streams) | 42.9–47.3 | 54.6–59.1% | 65.3–72.0% | 16.6–17.8% |
| A11c disjoint (500 single writes, 50 streams, column-elided) | 46.6–61.8 | 47.7–51.5% | 70.7–75.8% | 11.9–15.1% |
| A11c overlap (500 single writes, 50 streams, full fanout) | 91.8–113.8 | 33.8–42.0% | 72.4–78.1% | 9.2–9.7% |
| keyed PK subscriptions (200 random writes, 50 PK-watching streams) | 21.6–29.8 | 40.3–57.9% | 70.3–82.4% | 10.2–13.7% |
| wide batch insert (1 batch × 10,000 rows × 20 params) | 38.9–47.4 | 94.5–96.2% | 33.0–43.1% | 54.1–64.5% |

`parked_total` = 0 and `max_parked` = 0 on every scenario, reproducing exp
120 / exp 122's acceptance signal as a sanity check.

The headline split — `native / handler` — separates cleanly into two regimes:

- **Single Execute path (every A11c shape and keyed-PK):** the FFI write call
  accounts for 65–82 % of writer-isolate wall. Writer-side dispatch overhead
  per write is 11–21 µs.
- **Wide batch path:** the FFI write call accounts for only 33–43 % of writer
  wall. The Dart-side wrapper — almost entirely `allocateBatchParams` building
  the flat parameter matrix — consumes 24–27 ms out of a ~37–45 ms batch
  handler. As a fraction of total wall this is 54–64 %, because the batch
  handler itself is 95 % of wall (only one round-trip across the isolate
  boundary).

The third row also matters for the read side: `writer_handler / wall` on A11c
overlap is 34–42 %. Most of the overlap-fanout wall — 58–66 % — is outside the
writer isolate (main-isolate scheduling, in-flight reader fan-out, microtask
churn, the request/reply round-trip itself). Even an idealized writer-side
dispatch optimization that took `writer_handler` to zero would leave the
majority of overlap wall untouched.

## Decision

**Accepted (measurement).** Same outcome class as exps 115, 119, 121: the
implementation that lands here is the counters and harness, not an
optimization. Implementing-side conclusions:

- The `writer-isolate wall vs SQLite step wall split for overlap workloads`
  measurement gap on `stream-rerun-dispatch` is closed. The 34–42 % writer
  fraction of overlap wall is now a documented ceiling for any writer-area
  fanout change. Future fanout-latency work should look at the 58–66 % that is
  outside the writer (the remaining open candidate is "completion-side
  microtask scheduling cost counter").
- The `writer-isolate profile separating bind work from dispatch and step
  time` measurement gap on `parameter-encoding-and-binding` is closed. The
  33–43 % native fraction on the wide-batch path is the strongest signal
  surfaced by this audit: per-row Dart-side encoding dominates the writer's
  batch wall even after exp 113. A future batch-encoding experiment that
  shaved that path could move 24+ ms off the wide-batch handler — well
  inside per-benchmark decision threshold for the release suite's `Wide Batch
  Insert` row promoted by exp 116.
- The `writer dispatch wall counter (dart wall - SQLite step wall)` open
  candidate on `measurement-system` is no longer open.

A future writer-side implementation experiment is now expected to cite
`native / handler` and `writer_handler / wall` from this audit before
spending compile / iterate budget on a wall-time-only A/B.

## Future Notes

- The audit deliberately runs the same A11c / keyed-PK shapes
  `audit_workloads.dart` already exposes for exp 119 / 121, but does not
  *call* `audit_workloads.dart` because adding the writer-snapshot hook
  would have meant a structural change to a file two other audits
  depend on. The duplication is intentional and small; if a third
  writer-instrumented audit lands, factoring out the runner becomes
  worth doing.
- The writer-side counters live in `ProfileCounters` (writer-isolate
  scope) but are deliberately omitted from `ProfileCounters.snapshot()`
  — that map is main-isolate-local. Cross-isolate access goes through
  `Database.writerProfileSnapshot()`.
- The `Stopwatch?` parameter on the three FFI write helpers carries one
  null-check overhead in production (`?.start()` / `?.stop()` is a
  branch). Sub-nanosecond per call; symmetric across peers; safe.
- Run-to-run wall variance is ±20 % on overlap and ±15 % on the wide
  batch in this single-machine harness. The fractions are stable to a
  few percentage points run-to-run, which is what the decisions rest
  on. A future runner doing serious multi-run averaging should fold
  these scenarios into `diff_multirun.dart`'s aggregator if they need
  tighter intervals.
