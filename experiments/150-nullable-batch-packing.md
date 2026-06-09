# Experiment 150: Nullable batch parameter packing

**Date:** 2026-06-09
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Focused `batch_param_flatten`, `nullable-ascii`

## Problem

Experiments 125, 126, and 149 made guarded direct payload packing worthwhile for
large or repeated batch writes, but the live guard still had one first-row
blind spot:

```dart
_firstBatchRowHasString(paramSets.first, paramCount)
```

That cheaply avoided scanning numeric-only batches, but it also skipped the
packed encoder for nullable generated-statement shapes where row 0 has `NULL`
in text columns and later rows contain text. Those batches fell back to the
generic encoder even when they had the same width and total parameter count that
already justified direct ASCII packing.

The non-ASCII path also classified a guarded batch in two phases: try ASCII
measurement first, then rescan for UTF-8 byte lengths if any non-ASCII string
appeared. That was small for early non-ASCII rows, but avoidable in the same
bounded classifier.

## Hypothesis

Treat first-row `NULL` values as "may contain text", then classify guarded batch
payloads in one pass:

- if the batch contains only ASCII strings, use the existing ASCII packer;
- if it contains any non-ASCII string, use the existing direct UTF-8 packer;
- if it contains no strings, fall back to the generic encoder.

This should admit nullable first-row ASCII batches without reopening exp 146's
rejected 2-3 parameter broadening. Accept for review if nullable large rows
improve while existing ASCII and Unicode large-row guardrails stay neutral.

External contract checks stayed consistent with exp 126:

- Dart's `Utf8Encoder.convert` encodes unpaired surrogates as replacement
  characters: <https://api.dart.dev/dart-convert/Utf8Encoder/convert.html>
- SQLite `sqlite3_bind_text` accepts explicit byte lengths, preserving embedded
  NUL bytes when length is non-negative:
  <https://www.sqlite.org/c3ref/bind_blob.html>

## Approach

`allocateBatchParams` now keeps the same 6-parameter / 600-total guard from
experiment 149, but replaces the first-row string probe and split ASCII/UTF-8
measurement helpers with a single `_measureBatchPayload` pass.

The first row still acts as a cheap gate for stable non-text rows: if it has no
`String` and no `NULL`, the batch stays generic. When the first row has a
`String` or `NULL`, the classifier scans the guarded batch once and returns
`extraBytes`, `hasString`, and `isAscii`.

The focused benchmark gained `--text-mode=nullable-ascii`, where text columns in
row 0 are `NULL` and later rows are ASCII. This mode directly separates the old
first-row heuristic from the nullable-aware candidate while preserving the same
row-width matrix used by experiments 113, 125, and 126.

Correctness coverage adds a wide `executeBatch` case with nullable first-row
text and blob columns, proving the newly admitted shape preserves nulls, ASCII
text, and blobs.

## Results

Commands:

```text
dart run benchmark/experiments/batch_param_flatten.dart \
  --warmup=8 --iterations=40 --text-mode=nullable-ascii

dart run benchmark/experiments/batch_param_flatten.dart \
  --warmup=8 --iterations=40 --text-mode=ascii

dart run benchmark/experiments/batch_param_flatten.dart \
  --warmup=8 --iterations=40 --text-mode=unicode
```

The baseline worktree was `origin/main` at `72a2b92` with only the temporary
`nullable-ascii` benchmark mode applied. The candidate was
`exp-150-param-encoding-hotpath`.

Nullable first-row ASCII p50 wall time:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10,000 rows x 8 params | 13.552 ms | 11.152 ms | -17.7% |
| 10,000 rows x 20 params | 25.738 ms | 21.723 ms | -15.6% |
| 1,000 rows x 8 params | 1.177 ms | 1.132 ms | -3.8% |
| 1,000 rows x 20 params | 2.032 ms | 2.293 ms | +12.8% |

Existing ASCII fast-path guardrail:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10,000 rows x 8 params | 10.309 ms | 10.338 ms | +0.3% |
| 10,000 rows x 20 params | 21.625 ms | 20.179 ms | -6.7% |

Existing Unicode fast-path guardrail:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 10,000 rows x 8 params | 13.317 ms | 13.469 ms | +1.1% |
| 10,000 rows x 20 params | 29.085 ms | 30.499 ms | +4.9% |

The nullable target improves on the large rows that amortize batch payload
classification. The unchanged two-parameter rows still route through the
generic path; their movement in the local run is benchmark noise, not a changed
code path. The 1,000-row x20 nullable row was slower in this pass, so the
decision rests on the large-row shape that prior experiments already used as
the acceptance target.

## Decision

**Accept for review.**

This is an implementation experiment, not a measurement-only run. The change is
small, private to `allocateBatchParams`, and keeps exp 149's guard intact while
admitting a realistic nullable text shape that the previous first-row string
probe skipped. Existing ASCII and Unicode wide-batch guardrails stay within the
local benchmark noise band, and the target nullable large rows improve by
15-18%.

## Future Notes

Keep 2-3 parameter writes generic. This experiment does not weaken exp 146's
rejection; it only fixes the first-row-null blind spot once a batch is already
inside the six-parameter / 600-total guard.

If nullable generated-statement batches become a recurring product workload,
add a strict Tracelite scenario for that shape rather than continuing to rely on
the focused `batch_param_flatten` script.

## Validation

- `dart pub get`
- `dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart benchmark/experiments/batch_param_flatten.dart test/database_test.dart`
- `dart test test/database_test.dart --timeout 60s`
- Focused benchmark A/B:
  `benchmark/experiments/batch_param_flatten.dart --text-mode=nullable-ascii`
- Focused guardrails:
  `benchmark/experiments/batch_param_flatten.dart --text-mode=ascii`
  and `--text-mode=unicode`
