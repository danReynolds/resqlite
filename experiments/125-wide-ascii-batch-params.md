# Experiment 125: Wide ASCII batch parameter encoding

**Date:** 2026-05-05T18:20:00Z
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`

## Problem

Experiment 113 removed the temporary flattened Dart parameter list from
`executeBatch`, and experiment 116 promoted a 10,000-row x 20-parameter mixed
batch to the release write suite. That left a narrower question inside the same
hot path: wide generated-statement-style batches still allocate one temporary
`Uint8List` per text parameter before copying those bytes into the native
`[param structs][payload bytes]` buffer.

For common ASCII identifiers, slugs, tags, and generated fixture values, UTF-8
length is the Dart string length. The current generic path still pays
`utf8.encode` allocation for each string cell, then immediately copies the bytes
again into the native param arena.

## Hypothesis

For wide, large ASCII-heavy batches, a guarded ASCII encoder can skip the
temporary per-string `Uint8List` allocation and write code units directly into
the existing native payload tail. The fast path should improve 8- and
20-parameter batch rows while preserving the existing Unicode/blob behavior by
falling back to the generic encoder as soon as a non-ASCII string appears.

Accept if the focused 8- and 20-parameter batch shapes improve clearly, the
release-suite Wide Batch Insert improves under same-condition A/B, and
two-parameter/nested-batch guardrails remain neutral. Reject if the ASCII scan
cost erases the win or if the fallback semantics become fragile.

## Approach

`allocateBatchParams` now probes only large wide batches:

- `paramCount >= 8`
- `totalCount >= 8192`
- at least one string parameter
- every string is ASCII

When those conditions hold, `_allocateAsciiBatchParams` performs a direct pack:

1. Measure string/blob payload bytes without allocating encoded string lists.
2. Allocate the same native `[structs][payload bytes]` buffer used by the
   generic path.
3. Write integer, double, blob, null, and ASCII string parameters directly.
4. Use the existing generic encoder unchanged for all other cases.

Two local variants were rejected before this final shape:

- Stable column-kind specialization regressed the focused 10k x20 benchmark
  because the extra type-shape bookkeeping cost more Dart work than it removed.
- Raising the reusable native param buffer cap produced an unstable small win
  and introduced a memory tradeoff, so it was not kept.

A regression test covers a wide 8-parameter batch containing Unicode text and
blobs to prove non-ASCII values still use the generic fallback.

## Results

Focused command:

```text
dart run benchmark/experiments/batch_param_flatten.dart --iterations=60
```

Focused p50 wall time:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10,000 rows x 2 params | 3.829 ms | 3.613 ms | -5.6% |
| 10,000 rows x 8 params | 7.639 ms | 6.218 ms | -18.6% |
| 10,000 rows x 20 params | 17.199 ms | 12.760 ms | -25.8% |
| 1,000 rows x 8 params | 0.706 ms | 0.690 ms | -2.3% |
| 1,000 rows x 20 params | 1.376 ms | 1.139 ms | -17.2% |

Release write-suite same-condition command:

```text
dart run benchmark/suites/writes.dart
```

Same-condition p50 wall time:

| Write workload | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| Batch Insert (100 rows) | 0.097 ms | 0.089 ms | -8.2% |
| Batch Insert (1,000 rows) | 0.413 ms | 0.401 ms | -2.9% |
| Batch Insert (10,000 rows) | 3.998 ms | 3.848 ms | -3.8% |
| Wide Batch Insert (10,000 rows x 20 params) | 18.201 ms | 13.031 ms | -28.4% |
| tx.executeBatch (100 rows) | 0.105 ms | 0.100 ms | -4.8% |
| tx.executeBatch (1,000 rows) | 0.448 ms | 0.402 ms | -10.3% |

Validation:

```text
dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart test/database_test.dart
dart test test/database_test.dart test/transaction_test.dart --timeout 60s
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/suites/writes.dart
```

All passed. `build_runner` printed the existing warning that
`--delete-conflicting-outputs` has been removed and ignored, but generated the
needed Drift outputs.

## Decision

Keep in review.

The final fast path is bounded to the exact shape that measured: large wide
ASCII-containing batches. It preserves the lean public API, keeps the generic
Unicode/blob encoder as the correctness fallback, and improves both the focused
row-width benchmark and the release-suite wide batch row.

## Future Notes

Do not generalize this into a broad string encoder without new evidence. The
win comes from avoiding temporary UTF-8 lists in large wide batches; small
queries and non-ASCII text should stay on the generic path unless a future
profile shows their encoding cost is material.

If a future workload is non-ASCII-heavy, benchmark that directly before
changing the fallback. Correct Unicode handling is more important than forcing
the ASCII fast path to cover every string workload.
