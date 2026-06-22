# Experiment 191: embedded-NUL public API audit

**Date:** 2026-06-21
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none - correctness guard; no runtime code changed.

## Problem

The `parameter-encoding-and-binding` signal map kept one non-performance
candidate open: a broader embedded-NUL text handling audit across public APIs.
That candidate exists because text bind optimizations rely on explicit byte
lengths (`sqlite3_bind_text(..., len, ...)`) rather than C-string termination.
If any path accidentally treated TEXT as NUL-terminated, it would silently
truncate valid Dart strings.

Current main already covers the guarded wide `executeBatch` path with multibyte
and embedded-NUL text. The in-flight exp 187 branch adds a single-row
`execute` regression test while extending the UTF-8 bind encoder. The remaining
public surfaces without direct embedded-NUL assertions were:

- `Database.selectBytes()`, where native JSON encoding must emit a valid JSON
  string and preserve `\u0000` through `jsonDecode`.
- `Database.stream()`, where the one-pass initial decode, result hash, and
  re-query emission path must preserve embedded-NUL TEXT values.

## Hypothesis

If the reader-side JSON and stream decode paths use explicit lengths all the
way through, embedded-NUL text seeded inside SQLite should round-trip through
both public APIs with byte-identical UTF-8 payloads. No runtime implementation
change should be necessary; the expected outcome is durable coverage and a
closed signal-map candidate.

## Approach

Added two focused public API tests:

- `test/database_test.dart`: `selectBytes preserves embedded-NUL text` creates
  TEXT with SQLite `char(0)`, verifies `select()` returns the expected Dart
  string and `hex(CAST(body AS BLOB))` matches `_hexUtf8(body)`, then verifies
  `selectBytes()` decodes back to the same string.
- `test/stream_test.dart`: `preserves embedded-NUL text through stream
  emissions` creates `initial\0...` TEXT via SQLite `char(0)`, verifies the
  initial stream emission, updates the row to `changed\0...`, then verifies the
  re-emitted row and stored UTF-8 bytes.

The inserts deliberately use SQL `char(0)` instead of parameter binding so this
run isolates reader JSON / stream decode behavior from the parameter encoder
work already covered by main and exp 187.

## Results

Focused validation:

```text
dart test test/database_test.dart
50/50 tests passed

dart test test/stream_test.dart
28/28 tests passed
```

No runtime code changed. The new assertions prove the public reader surfaces
preserve embedded-NUL text and that the stream hash / unchanged-suppression
machinery still emits the changed row when the embedded-NUL value changes.

## Decision

**In Review.** This is a correctness guard, not a performance optimization.
The mapped embedded-NUL audit candidate is now consumed for the public surfaces
that were not already covered by main or exp 187. Future parameter work should
keep these tests alongside the existing wide-batch and single-row execute
guards whenever it changes `_utf8Length`, `_writeUtf8`, bind lengths, JSON
string emission, or stream row decoding.

## Future Notes

- Do not reopen broad embedded-NUL work without a new public API surface or a
  concrete regression report. The current coverage spans wide `executeBatch`,
  in-flight single-row `execute`, `selectBytes`, and stream emissions.
- A true performance follow-up in this direction still needs a workload where
  parameter encoding is material. This run does not change the existing
  guidance around blob-heavy or small/narrow parameter shapes.

## Validation

- `dart pub get`
- `dart format test/database_test.dart test/stream_test.dart`
- `dart test test/database_test.dart`
- `dart test test/stream_test.dart`
