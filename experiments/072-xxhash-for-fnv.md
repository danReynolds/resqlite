# Experiment 072: xxhash64 replacing FNV-1a for result change detection

**Date:** 2026-04-16
**Status:** Rejected

## Problem

Result change detection for reactive streams (`selectIfChanged` on the read
worker, `_hashResult` in `StreamEngine`) is on the hot path for every write
that invalidates a stream. The existing implementation in `result_hash.dart`
uses FNV-1a: a 64-bit prime-multiply + xor per combine step, plus a per-byte
loop for `Uint8List` content.

The hypothesis: xxhash64 is 2–3× faster than FNV-1a on typical byte streams,
so swapping the primitive might reduce stream invalidation latency.

## Hypothesis

Replacing FNV-1a with xxhash64 mergeRound for the combine step, and with a
full xxhash64 byte-hash for `Uint8List`, would be a drop-in speedup.

## Approach

Rewrote `lib/src/result_hash.dart` to implement xxhash64:

- `fnvCombine` (renamed semantically but kept for source compatibility)
  became an xxhash64 mergeRound: `round(0, v)` then `((acc * p1) + p4)`.
- `stableValueHash(Uint8List)` became a full xxhash64 byte-stream hash
  processing 32 bytes/iter via four parallel lanes, then 8-byte chunks,
  then the tail.
- `hashValues` accumulated merge-rounds over each pre-hashed value. A
  finalize step was dropped to preserve bit-for-bit equivalence with the
  client-side `StreamEngine._hashResult` path, which also skips finalize
  — we only need equality for suppression, not avalanche.

Functional tests passed once the finalize asymmetry was removed.

## Results

Measured with `dart run benchmark/run_all.dart --repeat=5` against a stable
baseline (`round1-baseline-stable.md`) captured on the same machine in the
same session to control for thermal state.

### Regressions on hash-path benchmarks

| Benchmark | Baseline (ms) | xxhash (ms) | Δ |
|---|---:|---:|---:|
| Streaming / Invalidation Latency | 0.04 | 0.07 | **+75%** |
| Streaming / Stream Churn (100 cycles) | 1.63 | 2.37 | **+45%** |
| Streaming / Fan-out (10 streams) | 0.15 | 0.20 | **+33%** |

All other benchmarks were within noise. No benchmark improved.

## Why It Didn't Work

xxhash64 is designed for byte-stream hashing, where it processes 32 bytes
per iteration via four parallel lanes — a huge win over per-byte FNV when
the input is raw bytes.

But the inputs to `hashValues` in resqlite are **pre-hashed 64-bit values**.
Each call to `_mergeRound(h, v)` folds one already-hashed `int`
(`String.hashCode`, `int.hashCode`, or the per-value byte hash for blobs)
into the accumulator. At that point:

- FNV-1a combine = 1 xor + 1 multiply. ~2 ns on M1.
- xxhash64 mergeRound = 1 multiply + 1 rotate + 1 multiply + 1 xor +
  1 multiply + 1 add. ~5 ns on M1.

With ~N·C merge calls per query (rows × cols), the per-combine cost
difference dominates. Bulk xxhash wins only when the hash function
consumes bytes directly — which would require hashing the raw cell
buffer in C before materialization (a separate, larger experiment).

The `Uint8List` byte-stream path (where xxhash is legitimately faster)
is never exercised in the current benchmark suite, which has no blob
columns.

## Decision

Rejected. Restored FNV-1a. The net regression is large and unambiguous on
the exact paths the experiment was meant to improve.

## Follow-ups

The real win for stream invalidation latency is not a faster hash function
over pre-hashed values — it's avoiding the materialization of Dart objects
when the hash is going to match anyway. A future experiment should hash
the raw C cell buffer in native code directly, short-circuiting the decode
loop when the hash matches the stored `lastResultHash`. That's a
structural change and deserves its own experiment (see Round 2 tier list).
