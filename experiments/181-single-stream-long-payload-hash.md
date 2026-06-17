# Experiment 181: Single-stream long-payload hash

**Date:** 2026-06-17
**Status:** Rejected
**Direction:** `long-text-stream-hashing`
**Benchmark Run:** focused harness only (`benchmark/experiments/single_stream_long_payload_hash.dart`); no release-suite run because the native candidate was reverted.

## Problem

Exp 110 accepted the 8-byte FNV byte-stream fold after the new 4 KB long-text
unchanged-fanout row showed a clear win over byte-at-a-time hashing. Exp 173
then tested a 16-byte unrolled fold against a 32 KB long-text workload and
rejected it: the candidate measured +4.5% and +12.1% versus the 8-byte body
across order-flipped passes.

The remaining uncertainty was whether exp 173 hid hash-loop overhead by
parallelizing eight unchanged streams across the normal reader pool. The signal
map left one explicit candidate: build a single-stream long-payload benchmark
that bypasses reader-pool parallelism, then use it to decide whether the
16-byte fold has any isolated public-API workload signal.

## Hypothesis

If the pool-of-4 fanout was masking the loop-control cost, a one-reader,
one-unchanged-stream workload should make the byte-stream fold more dominant.
Under that shape, the exp 173 16-byte fold might finally show a stable win over
the exp 110 8-byte body.

Acceptance criterion: the 16-byte fold must improve the focused single-stream
harness across an order-flipped A/B pair. Reject if the medians overlap or the
effect changes sign, because the public stream path still cannot see the loop
unroll.

## Approach

Added `benchmark/experiments/single_stream_long_payload_hash.dart`.

The harness uses internal runtime pieces so it can force a one-reader stream
engine without changing the public API:

- opens a native database with one reader;
- registers one unchanged stream selecting 64 rows of 64 KB ASCII TEXT plus
  64 KB BLOB, about 8 MB hashed serially per invalidation;
- registers a cheap `COUNT(*)` barrier stream after the long stream;
- inserts a row outside the long stream predicate and waits for the barrier's
  second emission, which can only happen after the one reader finishes the long
  unchanged hash pass.

Then re-tested the exp 173 16-byte candidate in `fnv_combine_bytes`:

```c
for (; i + 16 <= len; i += 16) {
  uint64_t w0, w1;
  memcpy(&w0, b + i, 8);
  memcpy(&w1, b + i + 8, 8);
  h ^= w0;
  h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
  h ^= w1;
  h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
}
```

The candidate preserves the same serial xor/multiply sequence as the 8-byte
body; it only halves loop-control overhead. Native code was reverted after the
measurement.

## Results

Focused harness, 2 warmup + 9 measured rounds per side.

| Pass | Order | Baseline 8-byte median | Candidate 16-byte median | Delta |
|---|---|---:|---:|---:|
| 1 | baseline first | 2.771 ms | 2.763 ms | -0.3% |
| 2 | candidate first | 2.777 ms | 2.792 ms | +0.5% |

Measured ranges:

| Side | Median | p90 | Min | Max |
|---|---:|---:|---:|---:|
| Baseline pass 1 | 2.771 ms | 3.150 ms | 2.636 ms | 3.150 ms |
| Candidate pass 1 | 2.763 ms | 3.066 ms | 2.659 ms | 3.066 ms |
| Candidate pass 2 | 2.792 ms | 3.015 ms | 2.642 ms | 3.015 ms |
| Baseline pass 2 | 2.777 ms | 2.974 ms | 2.655 ms | 2.974 ms |

The candidate is indistinguishable from the baseline. Removing reader-pool
parallelism did not make the 16-byte loop body visible.

## Decision

Rejected. The single-stream workload consumed the remaining open candidate and
refuted the premise that reader-pool parallelism was hiding a mergeable 16-byte
FNV win.

The 8-byte fold from exp 110 remains the right implementation. The 16-byte body
was reverted from `native/resqlite.c`; the harness is retained so a future
runner can recheck this path if a production profile makes long-payload
unchanged hashing hot again.

## Future Notes

- Do not retry FNV loop unrolling on the existing long-text, long-payload, or
  single-stream public stream workloads. Exp 173 and exp 181 now both show no
  stable win for the 16-byte body.
- If long-payload stream hashing becomes hot again, the next useful signal is a
  direct `resqlite_query_hash` microbenchmark or production profile that splits
  SQLite value access, hashing, reader dispatch, and reply delivery.
- The harness intentionally uses a one-reader internal runtime. That is a
  measurement tool, not a proposed public `Database.open` option.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos benchmark/experiments/single_stream_long_payload_hash.dart`
- `dart run benchmark/experiments/single_stream_long_payload_hash.dart` (baseline pass 1)
- `dart run benchmark/experiments/single_stream_long_payload_hash.dart` (candidate pass 1)
- `dart run benchmark/experiments/single_stream_long_payload_hash.dart` (candidate pass 2)
- `dart run benchmark/experiments/single_stream_long_payload_hash.dart` (baseline pass 2)
