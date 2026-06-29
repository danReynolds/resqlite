# Experiment 126: Wide UTF-8 Batch Parameter Packing

**Date:** 2026-05-06
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none (focused `benchmark/experiments/batch_param_flatten.dart` Unicode/emoji shapes; no exp-126 release artifact was committed at the time — see Results)

## Problem

Experiment 125 proved that wide ASCII-heavy batches still had removable
per-string `utf8.encode` allocation after exp 113's direct matrix encoder:
the accepted fast path writes ASCII code units directly into the native
parameter payload tail and falls back to the generic encoder for non-ASCII.

That left the exact follow-up called out in exp 125's future notes: before
generalizing the string encoder, benchmark a non-ASCII-heavy workload
directly. The generic fallback still allocates one temporary `Uint8List` per
non-ASCII string cell, then copies those bytes into the same native batch
payload buffer.

External contract checks:

- Dart's `Utf8Encoder.convert` encodes unpaired surrogate code units as
  `U+FFFD`: https://api.dart.dev/dart-convert/Utf8Encoder/convert.html
- SQLite `sqlite3_bind_text` accepts an explicit byte length; embedded NULs
  are preserved when the length is non-negative:
  https://www.sqlite.org/c3ref/bind_blob.html
- SQLite permits NUL characters in stored strings, though its CLI and some SQL
  functions display surprising truncated views:
  https://www.sqlite.org/nulinstr.html

## Hypothesis

For large wide non-ASCII batches, a guarded direct UTF-8 writer can skip the
temporary per-string `Uint8List` allocations and write UTF-8 bytes directly
into the already-allocated native parameter buffer. The fast path should
improve Unicode/emoji-heavy 8- and 20-parameter batch shapes while keeping the
existing ASCII path first and preserving Dart's malformed-surrogate semantics.

Accept if Unicode/emoji wide batches improve clearly, narrow/small controls
stay neutral, release write-suite rows do not show a targeted regression, and
round-trip tests cover multibyte text plus embedded NULs. Reject if the manual
UTF-8 scan/write cost erases the allocation win or the correctness surface
becomes fragile.

## Approach

The existing exp 125 guard remains the entry point:

- `paramCount >= 8`
- `totalCount >= 8192`
- the first row contains at least one string

`allocateBatchParams` still tries the ASCII path first. Only when the batch
contains a non-ASCII string does it use the new direct UTF-8 path:

1. Measure UTF-8 byte length without allocating encoded lists.
2. Allocate the same native `[structs][payload bytes]` buffer as the generic
   path.
3. Write UTF-8 bytes directly into the payload tail, including surrogate-pair
   handling and replacement-character encoding for unpaired surrogates.
4. Bind the exact byte length through the existing C-side `sqlite3_bind_text`
   call.

The focused benchmark now supports `--text-mode=unicode|emoji|nul` so future
experiments can reproduce the non-ASCII path instead of inferring from the
ASCII release row.

## Results

Focused command:

```text
dart run benchmark/experiments/batch_param_flatten.dart --iterations=50 --text-mode=unicode
dart run benchmark/experiments/batch_param_flatten.dart --iterations=50 --text-mode=emoji
```

Focused p50 wall time:

| Text mode | Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|---:|
| unicode | 10,000 rows x 8 params | 9.903 ms | 8.216 ms | -17.0% |
| unicode | 10,000 rows x 20 params | 21.945 ms | 18.988 ms | -13.5% |
| emoji | 10,000 rows x 8 params | 9.580 ms | 8.358 ms | -12.8% |
| emoji | 10,000 rows x 20 params | 24.187 ms | 17.458 ms | -27.8% |

Small/narrow controls stayed neutral:

| Text mode | Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|---:|
| unicode | 10,000 rows x 2 params | 4.420 ms | 4.515 ms | +2.1% |
| unicode | 1,000 rows x 8 params | 0.837 ms | 0.832 ms | -0.6% |
| unicode | 1,000 rows x 20 params | 1.618 ms | 1.615 ms | -0.2% |
| emoji | 10,000 rows x 2 params | 4.553 ms | 4.506 ms | -1.0% |
| emoji | 1,000 rows x 8 params | 0.815 ms | 0.881 ms | +8.1% |
| emoji | 1,000 rows x 20 params | 1.660 ms | 1.542 ms | -7.1% |

Release write-suite same-day guardrail:

| Workload | Baseline | Candidate | Delta | Read |
|---|---:|---:|---:|---|
| Batch Insert (100 rows) | 0.089 ms | 0.094 ms | +5.6% | neutral |
| Batch Insert (1,000 rows) | 0.392 ms | 0.415 ms | +5.9% | neutral |
| Batch Insert (10,000 rows) | 3.800 ms | 3.890 ms | +2.4% | neutral |
| Wide Batch Insert (10,000 rows x 20 params) | 13.148 ms | 13.484 ms | +2.6% | neutral |
| tx.executeBatch (100 rows) | 0.097 ms | 0.098 ms | +1.0% | neutral |
| tx.executeBatch (1,000 rows) | 0.398 ms | 0.431 ms | +8.3% | neutral |

Validation:

```text
dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart benchmark/experiments/batch_param_flatten.dart test/database_test.dart
dart test test/database_test.dart --timeout 60s
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/suites/writes.dart
```

All passed. `build_runner` printed the existing warning that
`--delete-conflicting-outputs` has been removed and ignored.

## Decision

**Accept for review.** The non-ASCII direct writer clears the target workload:
large wide Unicode batches improve 13-17%, and emoji-heavy batches improve
13-28%. The ASCII release suite remains on exp 125's first-choice path and
shows no targeted regression in same-day guardrails.

This preserves the lean public API and keeps the optimization private to the
batch parameter encoder. Correctness coverage now includes multibyte strings,
emoji/surrogate-pair text, blobs, and embedded NUL text on the guarded wide
batch path.

## Future Notes

Do not broaden this past large wide batches without a new benchmark. The win is
still from removing per-string temporary allocation in batch parameter packing;
small/narrow writes remain on the generic path because the scan/write overhead
does not have enough allocation work to amortize.

The remaining parameter-encoding questions are blob-heavy batch shapes and
whether any production workload needs broader embedded-NUL guarantees beyond
the batch path tested here.
