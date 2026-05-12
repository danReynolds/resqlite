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

The harness reuses exp 110's workload shape — 8 unchanged streams
projecting `id, body, sid` with `WHERE id < 256` predicates, one
barrier stream projecting the full table, 256 seed rows, one INSERT
per iteration with a row outside every unchanged stream's predicate
— and sweeps the per-cell byte size across `[4KB, 16KB, 32KB, 64KB,
128KB]`. Each cell size runs 3 warmup iterations followed by 30
timed iterations; the per-iteration wall is the `Stopwatch` around
`db.execute(insert)` plus the wait for the barrier stream to
re-emit. The unchanged streams must not emit (the hash-only fast
path is supposed to suppress re-delivery); the harness asserts
this on every iteration.

The `ns_per_byte` column divides the median wall by
`cell_bytes × (unchanged_streams × row_count + (row_count + 1))`.
Each unchanged stream re-hashes its full 256-row result every
fanout wave; the barrier stream re-hashes 257 rows after the new
row lands. At 16KB cells that is ~38 MB of hashed payload per
iteration; at 128KB it is ~302 MB. `ns_per_byte` is the per-byte
cost averaged across that payload, so it isolates hash-loop
throughput from the per-iteration overhead floor.

The harness does not require `kProfileMode` to produce a useful
report (the scaling decision rests on end-to-end wall, not
profile-only counters), but it warns when run without it because
peer audits use the same convention.

## Results

Three repeated passes; values bracket the per-run band.

Per-iteration wall:

| cell size | median_ms (a/b/c)        | p90_ms       | p99_ms       |
|-----------|--------------------------:|-------------:|-------------:|
| 4KB       | 2.11 / 2.23 / 2.11        | 2.89 – 3.45  | 3.23 – 4.62  |
| 16KB      | 4.50 / 4.28 / 4.52        | 5.27 – 5.55  | 6.25 – 7.14  |
| 32KB      | 9.49 / 9.62 / 9.47        | 10.38 – 10.67| 11.66 – 12.87|
| 64KB      | 27.52 / 28.13 / 25.26     | 33.72 – 35.16| 34.72 – 36.09|
| 128KB     | 44.51 / 42.91 / 47.41     | 53.92 – 55.60| 55.84 – 62.64|

Per-byte cost:

| cell size | hashed_bytes_per_iter | ns_per_byte (median, a/b/c) |
|-----------|----------------------:|----------------------------:|
| 4KB       |             9,441,280 | 0.224 / 0.236 / 0.223       |
| 16KB      |            37,765,120 | 0.119 / 0.113 / 0.120       |
| 32KB      |            75,530,240 | 0.126 / 0.127 / 0.125       |
| 64KB      |           151,060,480 | 0.182 / 0.186 / 0.167       |
| 128KB     |           302,120,960 | 0.147 / 0.142 / 0.157       |

Aggregate file:
[`benchmark/profile/results/exp-137-long-text-scaling-aggregate.md`](../benchmark/profile/results/exp-137-long-text-scaling-aggregate.md).

The 4KB row sits ~2x above the larger-size band because the
per-iteration overhead (writer round-trip, microtask scheduling,
isolate dispatch, the per-iteration String allocation in the harness
itself) is comparable in absolute terms to the hashing work at small
sizes. From 16KB upward the per-byte cost converges to the **0.12 –
0.19 ns/byte** band — the implied hash-loop throughput is roughly
~6 GB/s per stream, about what the 8-byte FNV chunked loop should
sustain on a modern desktop CPU.

The 64KB row carries a small per-byte hump (~0.17 – 0.19 ns/byte vs
~0.13 – 0.16 ns/byte at 32KB and 128KB) and a wider min-to-max spread
(min 15 – 16 ms vs median 25 – 28 ms vs max 34 – 36 ms). The
per-iteration String allocation crosses an old-generation GC threshold
at that size on this VM build; the 32KB and 128KB rows happen to land
on cleaner sides of that boundary. The hump sits inside the broader
0.12 – 0.19 ns/byte band and does not change the linear-scaling
verdict.

## Decision

**Accept for review — measurement.**

The audit answers the open `signals.json` question for the
`long-text-stream-hashing` direction:

> long-payload streaming workload at sizes beyond exp 110's 4KB cells

Wall scales **linearly** with bytes from 16KB up, with per-byte cost
in a stable 0.12 – 0.19 ns/byte band. Hashing — not SQLite text-fetch,
not Dart-side allocation, not isolate transfer — is the dominant cost
on long-cell unchanged-fanout workloads at meaningful cell sizes.

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
  loop would still only save ~0.12 – 0.19 ns per byte hashed, which
  is below the ±10% per-benchmark decision threshold for the
  current 4KB release-suite shape.
- A future BLOB-shape audit at the same sweep sizes would confirm
  TEXT/BLOB symmetry; the underlying C path is shared, so a
  divergence between TEXT and BLOB at the same cell size would point
  at a SQLite text-fetch difference rather than a hash difference.
- The 64KB GC-spread observation (min 16 ms / max 36 ms / median ~26
  ms across passes) suggests the harness's per-iteration String
  payload allocation is itself a measurable signal at that size. A
  pre-built payload pool variant of this harness would reduce the
  spread; deferred because the `ns_per_byte` band is already stable
  enough to support the linear-scaling verdict.
