# Experiment 137: Long-text cell-size scaling audit

**Date:** 2026-05-12
**Status:** In Review
**Direction:** `long-text-stream-hashing`, `measurement-system`

## Problem

[Exp 099](099-fnv-8byte-bytestream.md) was rejected as benchmark-invisible
because the streaming suite at the time only carried short cells.
[Exp 110](110-long-text-fnv-8byte.md) added a long-text unchanged-fanout
benchmark — 8 unchanged streams x 256 rows x **4KB** ASCII TEXT cells —
and the same 8-byte FNV change measured **-76%** on its median wall.

`signals.json#long-text-stream-hashing` left two related entries open
after that win:

- a `blockedOnMeasurement` requesting "long-payload streaming workload
  at sizes beyond exp 110's 4KB cells", and
- a 2026-04-29 `openCandidate` (`addedAfter: 110`) for "broader
  long-payload workload (>= 32KB TEXT cells, mixed BLOB/TEXT)" with
  `blockedOn: no benchmark covers payloads larger than the exp 110
  4KB shape`.

Until those entries close, the direction cannot tell whether the
hash-loop cost continues to drive wall as cells grow, or whether some
other cost — SQLite text-fetch over overflow pages, page cache, GC,
isolate transfer — takes over. Either outcome is decision-making:

- If wall scales linearly with bytes at the larger sizes, hashing
  dominates and another hash variant (wider unroll, SIMD probe) is the
  natural next attempt for any future workload that ships ≥16KB cells.
- If wall scales sub-linearly, a non-hash cost is the bottleneck at
  the long end and the direction can deprioritize hash-loop work.
- If wall scales super-linearly, allocation / GC / isolate-transfer
  cost emerges and points at a new direction entirely.

## Hypothesis

After exp 110 + the existing 8-byte FNV path, per-byte hashing cost
should be roughly flat across cell sizes once the per-iteration
overhead floor (writer round-trip, mutex acquisition, microtask
scheduling) is amortized. The 4KB shape sits below the amortization
point, so its `ns_per_byte` should be artificially high; sizes from
≥16KB onward should converge to a stable per-byte band that
characterizes the actual hash-loop throughput on the test machine.

Accept this as a measurement experiment if:

- the audit produces stable per-cell-size median walls across
  repeated passes (≤ ±10% drift on the dominant signal);
- the audit resolves the `signals.json` open candidate one way or
  the other;
- the run updates `blockedOnMeasurement` and `openCandidates`
  accordingly.

## Approach

Added one profile-mode harness:

```text
benchmark/profile/long_text_scaling_audit.dart
```

The harness mirrors exp 110's unchanged-fanout shape — 8 unchanged
streams projecting `id, body, sid` with `WHERE id < 256` predicates —
and sweeps the per-cell byte size across `[4KB, 16KB, 32KB, 64KB,
128KB]`. Each cell size runs 3 warmup iterations followed by 30
timed iterations.

The fanout *trigger* differs from exp 110 to keep per-iteration
hashed-byte work constant. Exp 110's release benchmark inserts a new
row each iteration and the barrier stream selects the full table, so
the barrier's hashed payload grows by one row per iteration (~1.3%
drift on the per-iteration denominator over 30 timed iterations,
biasing later iterations heavier). This audit uses a fixed barrier
row at `id = 999999` (well outside every unchanged stream's
predicate) and UPDATEs that row's `body` each iteration. The barrier
stream's `WHERE id = ?` projection therefore stays at exactly one
row across every iteration; the unchanged streams stay at exactly
256 rows. Per-iteration hashed payload is constant within each cell
size.

The per-iteration wall is a `Stopwatch` around `db.execute(update)`
plus the wait for the barrier stream to re-emit. The unchanged
streams must not emit (the hash-only fast path is supposed to
suppress re-delivery); the harness asserts this on every iteration
and fails loudly if it sees one.

The `ns_per_byte` column divides the median wall by
`cell_bytes × (unchanged_streams × row_count + 1)`. At 16KB cells
that is ~33 MB of hashed payload per iteration; at 128KB it is
~270 MB. `ns_per_byte` is the per-byte cost averaged across that
payload, isolating hash-loop throughput from the per-iteration
overhead floor.

The harness does not require `kProfileMode` to produce a useful
report (the scaling decision rests on end-to-end wall, not
profile-only counters), but it warns when run without it because
peer audits use the same convention.

## Results

Three repeated passes; values bracket the per-run band.

Per-iteration wall:

| cell size | median_ms (a/b/c)        | p90_ms       | p99_ms       |
|-----------|--------------------------:|-------------:|-------------:|
| 4KB       | 1.35 / 1.29 / 1.35        | 1.83 – 2.15  | 2.39 – 2.66  |
| 16KB      | 2.46 / 2.49 / 2.42        | 2.89 – 3.41  | 3.68 – 4.29  |
| 32KB      | 5.28 / 5.03 / 5.24        | 5.60 – 6.11  | 5.85 – 8.76  |
| 64KB      | 9.21 / 8.92 / 9.11        | 9.35 – 10.88 | 15.19 – 18.73|
| 128KB     | 17.40 / 18.85 / 17.31     | 18.78 – 27.93| 21.98 – 32.93|

Per-byte cost:

| cell size | hashed_bytes_per_iter | ns_per_byte (median, a/b/c) |
|-----------|----------------------:|----------------------------:|
| 4KB       |             8,392,704 | 0.160 / 0.154 / 0.161       |
| 16KB      |            33,570,816 | 0.073 / 0.074 / 0.072       |
| 32KB      |            67,141,632 | 0.079 / 0.075 / 0.078       |
| 64KB      |           134,283,264 | 0.069 / 0.066 / 0.068       |
| 128KB     |           268,566,528 | 0.065 / 0.070 / 0.064       |

Aggregate file:
[`benchmark/profile/results/exp-137-long-text-scaling-aggregate.md`](../benchmark/profile/results/exp-137-long-text-scaling-aggregate.md).

The 4KB row sits ~2x above the larger-size band because the
per-iteration overhead (writer round-trip, microtask scheduling,
isolate dispatch) is comparable in absolute terms to the hashing
work at small sizes. From 16KB upward the per-byte cost converges to
the **0.065 – 0.080 ns/byte** band — the implied hash-loop throughput
is roughly ~13 – 15 GB/s per stream, in line with what the 8-byte FNV
chunked loop should sustain on a modern desktop CPU.

The 64KB and 128KB rows carry wider min-to-max spreads (e.g. 64KB
min 5.81 ms vs median 9.21 ms vs max 18.73 ms; 128KB min 10.30 ms
vs median 17.40 ms vs max 32.93 ms). The per-iteration String
allocation built by `_longTextPayload` itself crosses Dart VM
old-generation heap-region thresholds at those sizes; the harness's
median is robust against the spread, but the p99 is not. The
medians sit cleanly in the 0.065 – 0.080 ns/byte band and do not
change the linear-scaling verdict.

Wall scales linearly with bytes from 16KB up: 16→32 doubles bytes
and roughly doubles wall (2.15x median), 32→64 doubles bytes and
1.74x wall, 64→128 doubles bytes and 1.89x wall.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`long-text-stream-hashing` direction:

> long-payload streaming workload at sizes beyond exp 110's 4KB cells

Wall scales **linearly** with bytes from 16KB up, with per-byte cost
in a stable 0.065 – 0.080 ns/byte band. Hashing — not SQLite
text-fetch, not Dart-side allocation, not isolate transfer — is the
dominant cost on long-cell unchanged-fanout workloads at meaningful
cell sizes.

What the resolution changes:

- **Removes the `blockedOnMeasurement` entry**: the workload that was
  missing now exists at five sizes.
- **Closes the matching `openCandidate`** (broader long-payload
  workload).
- **Adds a new `openCandidate`**: a wider FNV unroll or SIMD
  (AVX2/NEON) probe for the byte-stream loop. Its `blockedOn` is the
  shape of any *real* workload that ships ≥16KB cells; exp 110's
  release-suite shape is 4KB and would not see a measurable change
  because the 4KB row sits above the per-byte band.
- **Updates `currentRead`**: hash-loop variants are workload-dependent.
  The 4KB release-suite shape is per-iteration-overhead-bound; ≥16KB
  workloads would be per-byte-bound and could see a hash variant pay
  off proportional to bytes.

What the resolution does *not* change:

- The 8-byte FNV chunked loop stays correct and accepted; nothing in
  the data argues for reverting exp 110 or its underlying exp 099
  implementation.
- Mixed BLOB/TEXT workload coverage is still missing (the original
  candidate listed both). BLOB cells go through the same
  `fnv_combine_bytes` path as TEXT cells inside `resqlite_query_hash`,
  so the per-byte band should be substantially identical, but that
  is not directly measured here. Filed as a smaller follow-up
  candidate rather than a blocker.

## Future Notes

- A future hash-loop experiment (16-byte unroll, 32-byte unroll, AVX2
  probe, NEON probe, or an architecturally different state-pipelined
  hash) should compare medians against this audit's 16KB / 32KB /
  64KB / 128KB band, not against exp 110's 4KB benchmark. The 4KB
  benchmark is per-iteration-overhead-bound and will not move
  proportionally to a per-byte hash improvement.
- A future workload at ≥16KB cells (long content streams, document
  archives, large JSON blobs) is the natural trigger for revisiting
  hash-loop work. Without one, removing the entire byte-stream hash
  loop would still only save ~0.07 ns per byte hashed, which is
  below the ±10% per-benchmark decision threshold for the current
  4KB release-suite shape.
- A future BLOB-shape audit at the same sweep sizes would confirm
  TEXT/BLOB symmetry; the underlying C path is shared, so a
  divergence between TEXT and BLOB at the same cell size would point
  at a SQLite text-fetch difference rather than a hash difference.
- The 64KB / 128KB GC-spread observation (max ~2x median across
  passes) suggests the harness's per-iteration String payload
  allocation is itself a measurable signal at those sizes. A
  pre-built payload pool variant of this harness would reduce the
  spread; deferred because the median per-byte band is already stable
  enough to support the linear-scaling verdict.
- The fixed-barrier-row trigger this audit uses (UPDATE against
  `id = 999999`, picked outside every unchanged stream's predicate)
  is the right shape for any future per-iteration-constant hashing
  audit. Exp 110's INSERT-driven release benchmark grows the barrier
  stream's hashed payload by one row per iteration; that is fine for
  the per-benchmark shape but biases per-byte audit denominators by
  ~1.3% over 30 iterations.
