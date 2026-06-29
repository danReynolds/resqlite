# Experiment 175: Large selectBytes release coverage

**Date:** 2026-06-16
**Status:** Accepted
**Direction:** `result-transfer-shape`, `measurement-system`

## Problem

Exp 174 changed the large `selectBytes()` transfer policy: instead of copying
native JSON into a Dart `Uint8List` and sacrificing the reader isolate for
payloads above 256 KB, the reader now sends a transient view over its reusable
native `json_buf`. That won strongly in the focused harness, but the curated
release metric still tracked the existing 1K-row JSON-bytes result, which is
below the old sacrifice threshold and therefore mostly shows the small-result
copy path.

The release suite already had standard-row `selectBytes()` sizes, but the
dashboard/default experiment history did not have a named metric whose purpose
was "this exercises the large native bytes transfer path exp 174 changed."

## Hypothesis

Add a cheap, named large-payload `resqlite selectBytes()` row to the existing
release JSON-bytes suite and curate it into the experiment chart. The row should
stay above 256 KB so it guards the old sacrifice boundary and gives future
runners a visible regression signal for large bytes without running the full
focused exp 174 A/B every time.

This is measurement-support work, not a runtime optimization. It is justified
because it guards a recent accepted runtime path and lets future runners reject
or revisit selectBytes transfer-policy changes against a release-facing metric.

## Approach

`benchmark/suites/select_bytes.dart` now appends a `Large payload (~650KB)`
subsection after the standard 10 / 100 / 1K / 10K row-count tables. The new row:

- opens a dedicated resqlite database;
- seeds 2,000 rows with a 300-byte text body, producing a JSON payload above
  256 KB;
- throws if the probe result ever drops below 256 KB, so the row cannot silently
  stop exercising the large-bytes path;
- records only `resqlite selectBytes()` wall/main time, avoiding a full
  cross-peer 651 KB `jsonEncode` multiplication inside every release run.

`benchmark/shared/workload_registry.dart` now curates
`Large payload (~650KB) / resqlite selectBytes()` as
`selectBytes() large bytes` in the read chart.

No production runtime code changed.

## Results

Release-suite command:

```text
dart run benchmark/run_release.dart exp175-large-selectbytes-coverage --repeat=1 --no-auto-compare
```

Release artifacts:

- `benchmark/results/2026-06-16T06-19-03-exp175-large-selectbytes-coverage.md`
- `benchmark/results/2026-06-16T06-19-03-exp175-large-selectbytes-coverage.json`

New large-payload row from the release run:

| Row | Wall median | Wall p90 | Main median | Main p90 |
|---|---:|---:|---:|---:|
| Large payload (~650KB) / resqlite selectBytes() | 0.323 ms | 0.942 ms | 0.000 ms | 0.003 ms |

The standard rows still ran in the same pass. Headline existing
`selectBytes()` medians:

| Row count | Wall median | Main median |
|---|---:|---:|
| 10 rows | 0.018 ms | 0.000 ms |
| 100 rows | 0.051 ms | 0.000 ms |
| 1,000 rows | 0.361 ms | 0.000 ms |
| 10,000 rows | 3.545 ms | 0.000 ms |

The new row's main-isolate median stays effectively zero, which matches the
contract exp 174 was protecting: bytes are produced off-main and copied across
the isolate boundary, not encoded on the main isolate.

## Sensitivity — the lane provably responds to the transfer path

A guard is only worth adding if it *moves* when the thing it guards changes
(exp 148's lesson: callback counts dropped but measured elapsed did not). This
lane's workload — `resqlite selectBytes()` on a 651 KB result (2,000 × 300 B) —
is the exact shape exp 174's focused harness measured, where the view-send path
beat the old `fromList` + sacrifice path by **−44 % to −47 %** (269 µs vs
483 µs; `benchmark/experiments/large_bytes_transfer.dart`). A parallel attempt
at this same coverage ran the A/B directly on a release lane of the same band
and independently confirmed it: restoring the pre-174 path moved the row
**+13 % median / +55 % p90** (the respawn cost concentrates in the tail) while
adjacent standard lanes stayed neutral.

So a regression to the bytes-transfer path lands on this row rather than passing
silently — which is exactly what the existing lanes can't do: the **1K-row** lane
is < 256 KB (below the old sacrifice threshold, so it never exercised the path —
exp 174 calls it neutral), and the **10K-row** lane is wide enough that SQLite
stepping + JSON-gen dominate per-query wall and bury the transfer-path delta.
This row sits in the sub-millisecond, transfer-bound band where the delta is
visible.

## Decision

**Accept for review - measurement support.**

The experiment adds durable release coverage for the large `selectBytes()` path
without widening the public API or changing runtime behavior. This closes exp
174's immediate coverage gap: future benchmark histories now have a named
large-bytes metric instead of relying on the existing 1K row, which is too small
to guard the old sacrifice threshold.

## Future Notes

- Use `selectBytes() large bytes` as the release-facing guardrail before
  changing bytes transfer policy again.
- If memory-sensitive workloads show problematic `json_buf` high-water
  retention, compare any memory-reclaim threshold against this large-payload row
  first so reclaim work does not accidentally reintroduce the respawn cost exp
  174 removed.
- Do not treat this row as evidence for row-result transfer policy. Rows still
  intentionally keep the sacrifice path because `Isolate.exit` is a true
  object-graph handoff there.
