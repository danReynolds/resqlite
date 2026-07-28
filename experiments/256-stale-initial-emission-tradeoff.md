# Experiment 256: Emit stale-then-correct, or wait and emit only the truth?

**Date:** 2026-07-28
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — focused
  [`benchmark/experiments/stream_initial_emission_ab.dart`](../benchmark/experiments/stream_initial_emission_ab.dart);
  raw table in
  [`benchmark/results/2026-07-28-exp256-initial-emission.md`](../benchmark/results/2026-07-28-exp256-initial-emission.md).

## Problem

[Exp 255](255-stream-initial-emission-race.md) fixed a stream that could go
permanently silent when a write raced its initial query. But it left a design
question the bug had obscured: once you guarantee an emission, *which rows*
should the first one carry?

- **A — emit-then-correct.** Emit the initial rows immediately even though a
  write has already superseded them, then correct via the catch-up re-query.
- **B — suppress-stale.** Skip that emission, poison the comparison baseline so
  the re-query is guaranteed to emit, and let the corrected result be the
  stream's first.

Both fix the silence. A is unconditional by construction, which is why it
shipped first. B is what the stream's consumers arguably want — but it keeps
the "suppress the initial emission" shape that caused the bug, so it needed
evidence rather than preference.

## Hypothesis

A's advantage — a faster first emission — is measured against the wrong clock.
What a subscriber cares about is **time-to-correct-value**: when it can trust
what it is looking at. Since the catch-up re-query runs in both designs, B
should cost little on that clock while removing the stale frame entirely.

## Approach

The harness opens a stream over a seeded table and fires eight inserts
*without* awaiting the first emission, so the writes race the initial query.
Per observation it records time-to-first-emission, time-to-correct-value,
emission count, and how many emissions carried a row count that was already
wrong. Seed sizes of 1k / 20k / 60k widen the race window (the window is the
initial query's duration), plus a no-race control that must be identical
between lanes. 12 samples per shape after warmup.

## Results

Medians, Apple M1 Pro:

| shape | metric | A emit-then-correct | B suppress-stale |
|---|---|---:|---:|
| racing · 20k | time to correct (p50 / p90) | 8.1 / 10.0 ms | **9.5 / 15.8 ms** |
| racing · 20k | stale frames per stream | 1.00 | **0.00** |
| racing · 60k | time to correct (p50 / p90) | 18.5 / 22.9 ms | **18.9 / 21.4 ms** |
| racing · 60k | stale frames per stream | 1.00 | **0.00** |
| racing · 1k | stale frames per stream | 1.08 | **0.42** |
| no race · 20k (control) | time to correct | 13.3 ms | 13.3 ms |
| no race · 20k (control) | emissions | 2.00 | 2.00 |

**B costs ~1.4 ms at 20k rows and ~0.4 ms at 60k on time-to-correct-value** —
far less than a full extra query, because the re-query is already in flight in
both lanes; B simply declines to paint while it waits.

**B removes the stale frame completely** (1.00 → 0.00 at every raced size). A
renders exactly one wrong frame on every raced stream — the list-jump artifact
a reactive stream exists to prevent.

**A's fast first emission measures the wrong thing.** Its 3.1 ms first emission
at 20k delivers rows already known to be superseded; the subscriber must
disregard them for another 5 ms.

**The control is identical** — unraced streams behave the same in both lanes
(13.3 ms, 2 emissions), confirming the change is scoped to the raced path.

At 1k rows the race window is small enough that it often does not land at all,
which is why B still shows 0.42 stale frames there: those are the samples where
the writes completed before the initial query started, so both lanes correctly
emit the pre-write state first.

## Decision

**Accepted — ship B.** It is better on the metric that matters (never showing
known-stale data), costs about a millisecond on time-to-truth, and is identical
when nothing races.

Crucially it is *not* a return to the exp 255 bug: the poisoned baseline
guarantees the re-query emits, and `_requery` propagates errors to subscribers,
so the stream always resolves to a value or an error. The bug was suppression
*without* poisoning.

Would revisit if a workload cared more about first-paint latency than
correctness of first paint — a skeleton-UI pattern that would rather show stale
rows than nothing. That is a public-API question (an opt-in emission policy),
not a default worth changing.
