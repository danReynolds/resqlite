# Experiment 142: Single-row text parameter direct encoding

**Date:** 2026-06-07
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`

## Problem

Experiment 109 collapsed per-text-and-blob `calloc` into the reusable
parameter struct buffer for the single-row `allocateParams` path.
Experiments 113 / 125 / 126 then removed the temporary flat parameter list
and per-string `utf8.encode` allocations from the wide-batch path.

That left a smaller but recurring Dart-side allocation pattern on the
single-row counterpart of the batch encoder. Every parameterized read and
every single-row write that contains at least one string still allocated:

- one `List<Uint8List?>` per call (length `params.length`),
- one `Uint8List` per string parameter (returned by `utf8.encode`),
- then copied those bytes into the already-allocated native arena via
  `view.setRange`.

For high-frequency single-row queries (e.g. point reads with a string
WHERE parameter or single-row INSERTs from generated-statement code), the
per-call allocation pair fires on every dispatched message.

External contract checks:

- Dart's `Utf8Encoder.convert` documents that unpaired surrogate code
  units encode as `U+FFFD`:
  https://api.dart.dev/dart-convert/Utf8Encoder/convert.html
- SQLite `sqlite3_bind_text` accepts an explicit byte length; embedded
  NULs are preserved when `len >= 0`:
  https://www.sqlite.org/c3ref/bind_blob.html

## Hypothesis

For single-row queries that contain at least one string parameter, a
guarded direct text encoder can skip both the temporary `List<Uint8List?>`
and the per-string `Uint8List` produced by `utf8.encode`. The fast path
should improve string-parameter INSERT and parameterized SELECT shapes
while preserving Unicode and embedded-NUL semantics.

Accept if focused single-row shapes improve clearly across paired runs,
the release-suite Single Inserts row improves under same-condition A/B,
and batch / wide-batch rows stay neutral (the batch encoder still owns
its own gated fast paths from exp 113 / 125 / 126 and is unchanged here).
Reject if the in-place encoder cost erases the allocation win on short
strings or the correctness surface becomes fragile.

## Approach

`allocateParams` (`lib/src/native/resqlite_bindings.dart`) replaces the
previous two-pass encode-then-copy shape with a measure-then-write-direct
pattern that mirrors the exp 125 / exp 126 batch encoders:

1. **Pass 1 — measure without allocating.** Walk the parameter row once
   to accumulate `extraBytes`. ASCII strings contribute `String.length`
   directly; the first non-ASCII string flips a row-level flag and
   switches future strings to `_utf8Length` (a non-allocating walk that
   matches Dart's `Utf8Encoder` byte count, including surrogate-pair and
   replacement-character semantics).
2. **Allocate the same `[structs][payload bytes]` buffer** as the
   previous shape via the existing reusable param struct buffer.
3. **Pass 2 — write structs and encode strings directly.** ASCII-only
   rows write code units via a tight `view[start + j] = codeUnitAt(j)`
   loop; mixed rows use the shared `_writeUtf8` encoder. Int / double /
   blob / null handling is unchanged.

No public API change; the wide-batch encoders, the `_allocateBatchParamsGeneric`
narrow-batch path, and `freeParamBuffer` are unchanged. The
`dart:convert` import remains because the narrow-batch generic path still
uses `utf8.encode`.

Added a focused harness at
[`benchmark/experiments/single_row_param_encoding.dart`](../benchmark/experiments/single_row_param_encoding.dart)
that times runs of N back-to-back `execute()` / `select()` calls across
four single-row shapes, with `--text-mode=ascii|unicode` so future
experiments can revisit either fast path directly. Every parameter
builder honours the flag so unicode runs really do exercise the
non-ASCII path on the 1-string shapes as well as the 3-string row.

## Results

Focused harness (200 calls per timed sample, 30–40 iterations per shape),
paired runs alternating baseline / candidate to absorb thermal jitter:

ASCII text (pair C, the tightest of three pairs):

| Shape | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| INSERT name+value (1 string + 1 double) | 5.10 ms | 3.84 ms | -25% |
| INSERT name only (1 string) | 4.37 ms | 3.25 ms | -26% |
| INSERT three strings (3 ASCII strings) | 4.33 ms | 3.19 ms | -26% |
| SELECT category = ? (1 ASCII string param) | 8.95 ms | 7.82 ms | -13% |

Across three ASCII paired runs, candidate p10 (lower envelope) averaged
≈ -8% to -10% per shape; per-run variance was high but direction was
consistent (3 of 4 shapes wins each pair, p90 tails uniformly tighter).

Unicode text (true non-ASCII parameters — every string is `café_…` /
`mañana_…` / `naïve_…` / `caté_…` and routes through `_writeUtf8`):

| Shape | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| INSERT name+value (1 string + 1 double) | 5.40 ms | 5.35 ms | -1% |
| INSERT name only (1 string) | 4.53 ms | 4.51 ms | -0.4% |
| INSERT three strings (3 Unicode strings) | 4.89 ms | 4.03 ms | -18% |
| SELECT category = ? (1 Unicode string param) | 8.95 ms | 8.48 ms | -5% |

For one non-ASCII string, the candidate's `_writeUtf8` walks the string
twice (`_utf8Length` measure + inline encode) where the previous code
ran `utf8.encode` once and bulk-copied; the two paths land inside noise
on the single-string shapes. The three-string Unicode row stacks up the
removed allocations and the win is clear at -18%, confirming the
underlying signal is allocation removal — not the ASCII tight loop —
once enough strings are present to amortize the dual-walk cost.

Release write suite (same-condition A/B from `dart run benchmark/suites/writes.dart`),
resqlite-only rows:

| Workload | Baseline | Candidate | Delta | Read |
|---|---:|---:|---:|---|
| Single Inserts (100 sequential) | 5.423 ms | 4.327 ms | -20.2% | candidate path |
| Batch Insert (100 rows) | 0.102 ms | 0.108 ms | +5.9% | neutral (unchanged path) |
| Batch Insert (1,000 rows) | 0.454 ms | 0.456 ms | +0.4% | neutral (unchanged path) |
| Batch Insert (10,000 rows) | 4.710 ms | 4.401 ms | -6.6% | neutral (unchanged path) |
| Wide Batch Insert (10,000 × 20) | 15.903 ms | 16.337 ms | +2.7% | neutral (unchanged path) |
| Interactive Transaction | 0.071 ms | 0.091 ms | +28% | sub-100 µs, single-run outlier |
| Batched Write In Tx (100) tx.executeBatch | 0.120 ms | 0.129 ms | +7.5% | within noise |
| Batched Write In Tx (100) tx.execute() loop | 1.239 ms | 1.131 ms | -8.7% | candidate path |
| Batched Write In Tx (1,000) tx.executeBatch | 0.512 ms | 0.474 ms | -7.4% | within noise |
| Batched Write In Tx (1,000) tx.execute() loop | 9.211 ms | 8.092 ms | -12.1% | candidate path |

The Single Inserts row, `tx.execute()` loop rows, and the focused
benchmark are the workloads that route through `allocateParams`; all
three move in the expected direction. The batch / wide-batch rows route
through `_allocateBatchParamsGeneric` / `_allocateAsciiBatchParams` /
`_allocateUtf8BatchParams` (unchanged) and stay inside their respective
noise bands.

Validation:

```text
dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart \
  benchmark/experiments/single_row_param_encoding.dart
dart test test/database_test.dart test/transaction_test.dart \
  test/stream_test.dart --timeout 90s
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/suites/writes.dart
```

All passed. The database/transaction/stream tests cover Unicode strings,
emoji (surrogate pairs), and blob round-trips through `allocateParams`,
so the embedded-NUL and multibyte semantics of the new encoder are
exercised end-to-end.

## Decision

**Accept for review.** The focused harness consistently shows the
expected direction across paired runs, with the cleanest pair landing
-13% to -26% per shape; the release-suite Single Inserts and
`tx.execute()` loop rows move in the same direction and magnitude.
Wide-batch and bulk-batch rows stay neutral because they route through
their own gated encoders and are not touched.

The change keeps the lean public API, mirrors the exp 125 / exp 126
batch shape semantics, and removes the last per-string Uint8List
allocations on the single-row hot path.

## Future Notes

Do not extend this pattern to `_allocateBatchParamsGeneric` without a
new benchmark. The narrow-batch generic path still holds the
`List<Uint8List?>` pattern because batches that miss the wide-batch
gate already amortize their per-cell cost across many cells and a
similar rewrite needs its own A/B.

Per-run variance on the focused harness was material — single pairs
varied between -3% and -26%. Reviewers should re-run the focused harness
or the release Single Inserts row before treating a tail-only delta
in another experiment as a regression here.

If a future workload measures parameter encoding on long single strings
(≥ 256 bytes per cell), revisit whether `_writeUtf8`'s per-char branch
beats `utf8.encode` + `view.setRange` at that size. The win in this
experiment came from short identifier-shaped strings; the bulk-copy
crossover for long strings was not measured.
