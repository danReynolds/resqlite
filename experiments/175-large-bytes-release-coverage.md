# Experiment 175: Large-bytes selectBytes release coverage

**Date:** 2026-06-16
**Status:** In Review
**Direction:** `result-transfer-shape`, `measurement-system`

## Problem

[Experiment 174](174-selectbytes-view-transfer.md) dropped the reader
"sacrifice" path (Isolate.exit + reader respawn) for `selectBytes`. Above
`sacrificeByteThreshold = 256 * 1024` the worker formerly:

1. `Uint8List.fromList`-copied the native `json_buf` onto the Dart heap so
   Isolate.exit could transfer it, then
2. exited and respawned a fresh reader.

For bytes that copy was forced (native memory can't ride Isolate.exit as
owned) — so the zero-copy transfer saved nothing and only added the
respawn. After 174 the worker sends a `Uint8List` view over the
connection's persistent `json_buf` and never sacrifices. The focused
harness measured **−44 % (~1.8×)** on a 651 KB result and **−4 %** on
a 64 KB result, at a bounded ~+15 MB RSS high-water.

That harness is local (`benchmark/experiments/large_bytes_transfer.dart`).
The release suite (`benchmark/suites/select_bytes.dart`) only covered the
standard sizes `[10, 100, 1000, 10000]` against the standard 6-column
`items` schema:

- 1000-row JSON is **~190 KB** — below the 256 KB threshold, so this
  lane never crossed the sacrifice branch (174 calls it out as neutral).
- 10000-row JSON is ~1.9 MB but per-query wall is ~20 ms, dominated
  by SQLite stepping + JSON-gen; the transfer delta sits inside the
  noise on this size.

With no public lane whose result sits comfortably above 256 KB *and*
whose wall is dominated by the transfer path, future regressions to
exp 174's view-send shape would land invisibly on the release dashboard
— exactly the gap [exp 161](161-concurrent-writes-release-coverage.md)
filled for exp 159 on the writer side.

## Hypothesis

Adding one large-result row to `Select → JSON Bytes` will:

1. Force the result above 256 KB so the path 174 attacked is exercised
   on every release run.
2. Land per-query wall in the transfer-bound band (sub-ms), where
   the respawn cost shows up cleanly in median and especially p90.
3. Make any future regression to the bytes-transfer path public.

Accept if the new lane runs across all peers, the result clearly crosses
256 KB, and an A/B with the pre-174 path restored produces a measurable
delta on this lane (i.e. the lane is responsive to changes in the
mechanism it's there to guard).

## Approach

`benchmark/suites/select_bytes.dart` adds one new subsection after the
standard sizes loop:

```text
2000 long rows (≈700 KB result)
```

Shape:

- Reuses the standard `items` schema (no drift schema change).
- 2000 inserted rows with a wide ~320-byte `description` body so each
  JSON-encoded row reaches ~430 bytes.
- Measured payload: **883,933 B (864 KB)** — well above the 256 KB
  sacrifice threshold.
- Same per-peer comparison as the other lanes (4 peer `select() +
  jsonEncode` lines + 1 dedicated `resqlite selectBytes()` line).
- Same `defaultWarmup` / `defaultIterations` policy.

`_benchmarkAtSize` gains an optional `rowBuilder` parameter (threaded
into `seedPeer` and `seedResqlite`, which already accepted one); the
existing call sites pass nothing and keep the standard row. No
production source files are touched.

## Results

Command (in this worktree, paired smoke runs):

```text
dart run benchmark/suites/select_bytes.dart
```

### Candidate (exp 174 view-send) on the new lane

Two back-to-back passes:

| Pass | resqlite selectBytes wall med | wall p90 |
|---|---:|---:|
| 1 | 0.777 ms | 0.831 ms |
| 2 | 0.806 ms | 0.827 ms |

Adjacent lanes (1000 rows, 10000 rows) ran normally with no shape
change.

### Lane-sensitivity A/B (temporary pre-174 baseline)

Restored the pre-174 SelectBytesRequest path in `read_worker.dart`
(`Uint8List.fromList` + `sacrifice = length > 256 KB`), reverted after.

| | wall med | wall p90 |
|---|---:|---:|
| candidate (view-send, mean of two passes) | **0.79 ms** | **0.83 ms** |
| baseline (pre-174 fromList + sacrifice) | **0.91 ms** | **1.86 ms** |
| delta | **−13 %** | **−55 %** |

The respawn cost (~2-5 ms when it fires) lives in the tail: median
moves ~−13 % while p90 moves ~−55 %. Both directions match exp 174's
focused result — proportionally smaller in absolute terms because the
release harness's Stopwatch + warmup + iteration count distributes
the respawn over a different scale than the focused harness's tight
inner loop. The release lane is exp-174-sensitive, which is the
property that makes it a guard.

### Full subsection (candidate, run 1)

| Library | Wall med | Wall p90 |
|---|---:|---:|
| resqlite + jsonEncode | 7.725 ms | 9.942 ms |
| sqlite3 + jsonEncode | 9.892 ms | 12.306 ms |
| sqlite_async + jsonEncode | 11.142 ms | 11.960 ms |
| drift + jsonEncode | 12.269 ms | 13.171 ms |
| resqlite selectBytes() | **0.777 ms** | 0.831 ms |

The `resqlite selectBytes()` line is ~10× faster than the best
encode-path peer on this lane — the same band exp 174's focused
harness measured for 651 KB results (~269 µs/query, candidate).

### Validation

```text
dart pub get
dart run build_runner build
dart analyze benchmark/suites/select_bytes.dart  # No issues found!
dart run benchmark/suites/select_bytes.dart       # full suite completes
```

## Decision

**In Review — measurement coverage.**

The change is benchmark-only: no production source file is modified.
Its value is that the release suite now tracks the workload dimension
exp 174 attacked. The new lane:

- Sits in the sub-ms band where the bytes-transfer cost is a
  meaningful fraction of wall (unlike the 10000-row lane, where
  SQLite stepping dominates).
- Crosses the 256 KB sacrifice threshold by a comfortable margin
  (864 KB measured) so the path 174 attacked is always taken.
- Responds to changes in the underlying transfer mechanism (the
  A/B above moved median −13 % and p90 −55 % between baselines).

Two named decisions this lane unlocks for future runners:

- **Guard exp 174 publicly.** Any future change that re-introduces
  the `fromList` copy or sacrifice path for large-byte results will
  show up on this lane during release-suite runs, no focused harness
  required.
- **Gate future bytes-transfer experiments.** Anyone retrying the
  reopened candidates in exp 174's `nextSignals` (high memory-reclaim
  threshold for bytes >8 MB, C-side `json_buf` shrink, recycled
  warm-buffer pool) can compare their delta against this lane
  alongside the focused script.

## Future Notes

- Do not add a sweep of payload sizes here. One lane is enough to keep
  the public dashboard honest; focused sweeps stay in
  `benchmark/experiments/large_bytes_transfer.dart` and the
  256 KB → 64 MB sweep in `benchmark/experiments/transfer_mechanism_ab.dart`.
- The lane stays on the standard `items` schema deliberately — adding
  a separate drift table would force a `.g.dart` regen for every
  variation and the standard schema already exercises the same
  transfer path. Per-row body size, not column count, controls the
  payload here.
- If the rows `select()` path ever gains a similar transport
  optimization (currently exp 174 explicitly keeps sacrifice for
  rows because the zero-copy object transfer is real), use the
  existing `select_maps` and `resultset_foreach_consumer` lanes
  rather than promoting another bytes lane.
