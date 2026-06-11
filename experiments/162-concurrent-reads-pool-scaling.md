# Experiment 162: Sustained concurrent reads + reader-pool cap re-test

**Date:** 2026-06-11
**Status:** In Review
**Direction:** `stream-rerun-dispatch`

This run executes the paired-measurement rule added to
`RUNNER_INSTRUCTIONS.md`: the measurement (a sustained concurrent-reads
workload) and the implementation it unlocks (re-testing the reader-pool
cap that exp 105 rejected) are delivered together, with both results.

## Problem

The stream-rerun-dispatch signal map has carried an open candidate since
2026-04-30: *"a long-running concurrent-reads workload that sustains
parked dispatchers past pool size"*. Exp 105 rejected raising the pool
cap (4 → 8) on writer-fan-out shapes, and exp 114's dispatch work died
when exp 106 elided its workload — both rejections note that
parallelism should help only when concurrent reads saturate the pool,
a shape no benchmark exercised. Since then, exps 118/120/122
restructured dispatch (FIFO waiters, bounded admission, concrete-pool
construction), so per the journal's re-run rule ("the rejection's
reason must have changed"), the cap question is legitimately open
again — but only against a workload that can actually see it.

## Hypothesis

A reads-only workload (no streams, no writes — nothing column elision
or hash suppression can elide) with more clients than workers will
sustain parked dispatchers (verifiable via the exp 115 counters), and
against it a larger pool cap may now win without the completion-churn
regression exp 105 measured pre-118/120/122.

## Approach

**Measurement** — `benchmark/profile/sustained_concurrent_reads_audit.dart`:
8/16/32 concurrent clients looping point + range selects over a 5,000-row
table (warmup pass, then 400 ops/client measured), reporting throughput
plus `dispatcher_parked_total` / `max_parked` / `wake_retries`.

**Implementation under test** — a compile-time pool-cap override
(`-DRESQLITE_READER_CAP=n` in `Database.open`; const-folded, tree-shaken
at default, not public API), used to A/B caps 4/6/8/12 on the new lane
and caps 4/8 on the exp-147 guardrail workloads.

## Results

### Measurement: the lane sustains parking (counter gate satisfied)

Default cap 4:

| clients | ops/ms | parked_total | max_parked | wake_retries |
|---:|---:|---:|---:|---:|
| 8 | 36.5 | 3,176 / 3,200 | 4 | 0 |
| 16 | 63.7 | 6,393 / 6,400 | 12 | 0 |
| 32 | 75.8 | 12,795 / 12,800 | 28 | 0 |

Virtually every request parks; max depth = clients − cap; zero wake
retries (exp 118's FIFO waiters hold under sustained overload).

### Implementation: cap raise helps reads modestly…

| cap | 8 clients ops/ms | 16 | 32 |
|---:|---:|---:|---:|
| 4 | 36.5 | 63.7 | 75.8 |
| 8 | 43.5 | 58.0 | 83.4 |
| 12 | 50.4 | 75.8 | 86.8 |

+10–38% on the reads lane depending on shape (single-pass; the cap-6
32-client run produced an outlier and is omitted). Gains are sublinear —
throughput stays round-trip-bound, exactly as the exp 105 journal lesson
predicts.

### …and the fan-out guardrails still reject it

Exp-147 audit harness, cap 4 vs 8, same machine back-to-back:

| workload | cap 4 | cap 8 | delta |
|---|---:|---:|---:|
| A11c overlap | 127.8 ms | 174.1 ms | **+36%** |
| keyed PK subscriptions | 24.7 ms | 31.8 ms | **+29%** |
| A11c disjoint | 58.8 ms | 56.9 ms | neutral |

Exp 105's completion-churn mechanism survives the exp 118/120/122
dispatch restructuring: more workers complete more `selectIfChanged`
replies concurrently, and their completions queue ahead of pending
writes (A11c overlap emissions during the burst also rose 33 → 78).

## Decision

**Measurement accepted; cap raise rejected — and the rejection is now
current.** The reads-lane win (+10–38%) cannot pay +29–36% on the
canonical stream workloads. This upgrades exp 105's rejection from
"measured against a pre-118/120/122 dispatch structure" to "re-confirmed
on the current one", closes the 2026-04-30 open candidate, and leaves a
permanent reads-saturation lane plus the counter gate for any future
pool-scheduling idea. The `-DRESQLITE_READER_CAP` define stays as
experiment tooling (zero-cost at default, not API).

## Future Notes

- A static cap cannot serve both shapes; if read-heavy use cases become
  real, the options are the TODO-sanctioned `Database.open` max-reader
  option (API decision, maintainer's call) or an elastic pool that grows
  under sustained read parking and shrinks under writer fan-out — the
  parked counters this run validated are exactly the signal an elastic
  policy would consume.
- The reads lane is profile-mode only; promote a release-suite variant
  if pool-scheduling work becomes active (exp 116 pattern).
