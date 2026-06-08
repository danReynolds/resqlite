# Experiment 135: Reused BLOB batch packing

**Date:** 2026-06-07
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`

## Problem

Experiment 126 left one parameter-encoding question open: blob-heavy batch
shapes. The current batch encoder already writes `Uint8List` bytes inline into
the single native parameter arena, so a generic "direct BLOB writer" would not
remove a temporary allocation the way exp 125 and exp 126 did for text.

One narrower repeated-payload case still had removable work. If the same
`Uint8List` object appears many times in a large wide `executeBatch` matrix,
the encoder copied that payload into the native arena once per parameter even
though the batch runner binds and steps synchronously while the arena remains
alive.

## Hypothesis

For large wide batches with repeated large BLOB objects, copy each repeated
`Uint8List` object once into the native arena and point duplicate BLOB params
at the first copy. This should reduce Dart-side marshalling time and temporary
native allocation size without changing public API semantics.

Accept if isolated marshalling improves clearly on reused large-BLOB wide
batches, fresh/tiny BLOB rows avoid the full identity-map path, and existing
batch correctness plus write-suite guardrails pass. Reject if identity tracking
cost erases the win or if the implementation needs byte-equality comparison,
hashing, or public API changes.

## Approach

`allocateBatchParams` now samples only large wide batches before enabling BLOB
reuse:

- `paramCount >= 8`
- `totalCount >= 8192`
- sampled BLOBs are at least 64 bytes
- the first 32 rows contain repeated `Uint8List` object identity

When the sample finds repeated large objects, the payload sizing pass builds an
identity map from each unique BLOB object to its relative payload offset.
During packing, the first occurrence copies bytes into the native arena and
duplicates reuse that pointer. If the full pass saves less than 4096 bytes, the
plan falls back to the existing one-copy-per-param layout.

The focused batch benchmark now supports:

- `--blob-bytes=N`
- `--blob-mode=fresh|reused`
- `--measure=execute|marshal`

The `marshal` mode times only `allocateBatchParams` / `freeParamBuffer`, which
keeps this parameter-packing experiment separate from SQLite's unavoidable
storage copy for BLOB inserts.

## Results

Focused marshal command:

```text
dart run benchmark/experiments/batch_param_flatten.dart --measure=marshal --warmup=20 --iterations=100 --blob-bytes=256 --blob-mode=reused
```

Focused p50 marshalling time:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 1,000 rows x 8 params | 0.471 ms | 0.184 ms | -60.9% |
| 10,000 rows x 8 params | 4.154 ms | 1.338 ms | -67.8% |
| 1,000 rows x 20 params | 0.962 ms | 0.298 ms | -69.0% |
| 10,000 rows x 20 params | 11.763 ms | 6.236 ms | -47.0% |

The end-to-end execute benchmark was noisier because 256-byte BLOB inserts are
dominated by SQLite storage work, but the wide reused-BLOB rows still trended
in the expected direction. The release write suite, whose wide-batch guardrail
uses fresh tiny BLOBs, completed successfully on the candidate:

```text
dart run benchmark/suites/writes.dart
```

Candidate write-suite guardrail:

| Workload | resqlite p50 | resqlite p90 |
|---|---:|---:|
| Batch Insert (100 rows) | 0.145 ms | 0.836 ms |
| Batch Insert (1,000 rows) | 0.459 ms | 1.136 ms |
| Batch Insert (10,000 rows) | 5.149 ms | 9.055 ms |
| Wide Batch Insert (10,000 rows x 20 params) | 14.943 ms | 26.278 ms |
| tx.executeBatch (100 rows) | 0.120 ms | 0.249 ms |
| tx.executeBatch (1,000 rows) | 0.472 ms | 0.881 ms |

Validation:

```text
dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart benchmark/experiments/batch_param_flatten.dart test/database_test.dart
dart test test/database_test.dart --timeout 60s
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/experiments/batch_param_flatten.dart --measure=marshal --warmup=20 --iterations=100 --blob-bytes=256 --blob-mode=reused
dart run benchmark/suites/writes.dart
```

All passed. `build_runner` printed the existing warning that
`--delete-conflicting-outputs` has been removed and ignored.

## Decision

Accept for review.

This is a bounded private optimization for repeated large BLOB object identity
in large wide batches. It does not attempt byte-equality deduplication, does not
change parameter semantics, and preserves the existing fast paths for text,
fresh BLOBs, and small/narrow rows.

## Future Notes

Do not broaden this into byte-equality BLOB deduplication without a workload
that proves hashing or comparing payload bytes beats just copying them.
Repeated object identity is cheap to detect and safe to share inside the
synchronous batch arena; equal-but-distinct payloads are a different problem.

Use `--measure=marshal` for future parameter-packing work when SQLite stepping
or storage copies would hide the encoder signal in end-to-end `executeBatch`
timings.
