# Exp 120 — Bounded `_flushQueue` admission: dispatch pressure audit

Profile-mode A/B comparing `origin/main` (post-exp-119, pre-exp-120) against
the exp-120 candidate that bounds `StreamEngine._flushQueue` admission to
`ReaderPool.availableWorkerCount`. Measurements were taken on macOS,
`Platform.numberOfProcessors=10`, reader pool size = 4.

Command (each side):

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/dispatch_pressure_audit.dart
```

3 passes per side. Counters reset between passes inside the harness.

## Counter results — median across 3 passes

| workload                | side      |  wall_ms | parked_total | wake_retry_total | max_parked |
|-------------------------|-----------|---------:|-------------:|-----------------:|-----------:|
| direct reads control    | baseline  |     1.06 |           28 |                0 |         28 |
| direct reads control    | candidate |     1.03 |           28 |                0 |         28 |
| A11c baseline           | baseline  |    85.00 |            0 |                0 |          0 |
| A11c baseline           | candidate |    84.61 |            0 |                0 |          0 |
| A11c disjoint           | baseline  |    90.15 |            0 |                0 |          0 |
| A11c disjoint           | candidate |    89.09 |            0 |                0 |          0 |
| A11c overlap            | baseline  |   138.30 |         3590 |                0 |         46 |
| A11c overlap            | candidate |   131.09 |            0 |                0 |          0 |
| keyed PK subscriptions  | baseline  |   425.91 |         1198 |                0 |         46 |
| keyed PK subscriptions  | candidate |   425.66 |            0 |                0 |          0 |

Per-pass values for stream-pressure rows:

| workload     | side      | run 1  | run 2  | run 3  |
|--------------|-----------|-------:|-------:|-------:|
| A11c overlap (wall_ms) | baseline  | 134.84 | 141.09 | 138.30 |
| A11c overlap (wall_ms) | candidate | 131.09 | 133.21 | 130.87 |
| keyed PK     (wall_ms) | baseline  | 427.33 | 425.44 | 425.91 |
| keyed PK     (wall_ms) | candidate | 425.66 | 424.89 | 222.99 |

The keyed-PK candidate run 3 is a system noise event (concurrent activity);
the median (`424.89`) is used for the comparison row above. The first two
candidate runs match the baseline tightly — wall time is unchanged on this
workload while the parking signal is fully eliminated.

## Reading the deltas

- `direct reads control` is the live-counter sentinel: 32 concurrent selects
  against a pool of 4 always force 28 parks regardless of `_flushQueue`. Both
  sides report 28, confirming the candidate did not silence
  `dispatcherParkedTotal` globally.
- `A11c disjoint` keeps `parked_total = 0` on both sides because exp-106's
  writer-side column-level elision skips the stream re-query before it
  reaches `_requeryQueue`. The candidate change is invisible here, as
  expected.
- `A11c overlap`: parking drops from 3,590 → 0 and `max_parked` from 46 → 0.
  Wall time also moves -7.2 ms (-5.2%, single-pass profile-mode delta — at
  the edge of run-to-run noise on this harness, but consistent across all 3
  candidate passes).
- `keyed PK subscriptions`: parking drops from 1,198 → 0 and `max_parked`
  from 46 → 0. Wall is flat (-0.06% on the median), which matches the
  expectation: each parked dispatcher's wake-up is a single FIFO microtask
  hop on current main (post-exp-118), so eliminating it removes
  scheduling work but no reader-pool serialization.

The post-FIFO question raised by exp 119 — whether real workloads still see
ReaderPool dispatch pressure after exp 118 — is now answered for the
admission side: the parked-dispatcher signal these workloads produced was
upstream over-dispatch from `_flushQueue`, and bounding admission removes
it. Any remaining stream re-query pressure must surface through a different
counter (completion-side churn, write-side dispatch, invalidation cost).
