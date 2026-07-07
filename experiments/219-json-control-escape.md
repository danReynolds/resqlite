# Experiment 219: Direct JSON control-character escapes

**Date:** 2026-07-07
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_text_string_reserve.dart`](../benchmark/experiments/select_bytes_text_string_reserve.dart);
  raw pass tables in
  [`benchmark/results/2026-07-07T13-42-41Z-exp219-json-control-escape.md`](../benchmark/results/2026-07-07T13-42-41Z-exp219-json-control-escape.md).

## Problem

[Exp 202](202-text-json-string-reserve.md) rejected the broad safe-string
reservation candidate for `json_write_string`: reserving quote + payload +
quote once did not move safe ASCII TEXT lanes enough to keep the runtime
change. Its future notes deliberately kept narrower TEXT encoder mechanisms
open, including escaped control-character formatting.

The remaining control-character path was small but expensive:

```c
char ubuf[7];
snprintf(ubuf, sizeof(ubuf), "\\u%04x", c);
buf_write(b, ubuf, 6);
```

That path fires for TEXT bytes below `0x20` that do not have a named JSON
escape (`\b`, `\f`, `\n`, `\r`, and `\t` already use the two-byte escape
table). For embedded separators, binary-ish text, or data that carries control
markers, every affected byte pays a stdio formatter call even though the JSON
spelling is always `\u00XX`.

## Hypothesis

Writing the six JSON escape bytes directly from a small hex table should remove
the formatter cost while preserving output exactly. The target control-character
lane should reproduce a large win across an order-flipped focused A/B. Safe
ASCII, named escaped text, mixed rows, and narrow rows should stay neutral
because they do not use the changed helper.

## Approach

The runtime change is limited to [`native/resqlite.c`](../native/resqlite.c):

- add `json_hex_digits`;
- add `json_write_u00_escape`, which `buf_ensure`s six bytes and writes
  `\\u00` plus two lowercase hex digits directly into `json_buf`;
- replace only the `snprintf("\\u%04x")` fallback inside `json_write_string`.

The existing SWAR safe-byte scan, named escape table, span flushing, buffer
growth policy, and public `selectBytes()` API stay unchanged. JSON output stays
byte-identical because `snprintf("%04x")` already emitted lowercase hex, and
all values on this fallback path are single bytes below `0x20`.

The focused TEXT harness gained a `control` mode that inserts `0x01`, `0x02`,
and `0x03` into TEXT cells. This keeps exp 202's safe/named-escape/mixed guards
while adding a lane that actually exercises the changed code.

## Results

Focused harness:
`dart run benchmark/experiments/select_bytes_text_string_reserve.dart`.
Values are median microseconds per `selectBytes()` query.

| Lane | Baseline P1 | Candidate P1 | Delta P1 | Baseline P2 | Candidate P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 short ASCII text | 3019 | 2957 | -2.1% | 3005 | 2906 | -3.3% |
| 10k rows x 20 short ASCII text | 7120 | 6280 | -11.8% | 7113 | 6450 | -9.3% |
| 10k rows x 8 medium ASCII text | 6811 | 4055 | -40.5% | 3990 | 5594 | +40.2% |
| 10k rows x 8 escaped text | 7346 | 7090 | -3.5% | 7464 | 7855 | +5.2% |
| **10k rows x 8 control text** | **35927** | **6371** | **-82.3%** | **35824** | **6370** | **-82.2%** |
| 10k rows x 8 mixed (4 text + 2 int + 2 real) | 5562 | 5421 | -2.5% | 7253 | 5588 | -23.0% |
| 1k rows x 2 short ASCII text | 132 | 115 | -12.9% | 127 | 112 | -11.8% |

The target control-character lane reproduced almost exactly across the order
flip: roughly `35.9 ms -> 6.37 ms` per query in both pairings. That is the only
lane that is both mechanism-heavy and changed by this branch.

The non-target rows are guardrails, not the decision rows. Safe ASCII and named
escaped text do not use `json_write_u00_escape`; they stayed noisy in the same
TEXT harness style exp 202 already exposed. Medium ASCII flipped direction
between pairs, escaped text stayed within a few percent, and mixed/narrow rows
moved without a changed mechanism. There is no reproduced regression on a
mechanically touched guard.

Focused correctness:

```bash
dart test test/database_test.dart --name selectBytes
```

All 9 selected tests passed, including JSON special characters, embedded-NUL
TEXT, `jsonEncode(select())` equivalence, int64 extremes, integer-valued REALs,
and BLOB base64.

## Decision

**Accepted.**

Keep the runtime change. It removes `snprintf` from a real TEXT escape path,
reproduces an ~82% win on the targeted control-character lane, preserves the
common safe-string path, and keeps JSON bytes unchanged. The implementation is
small enough that there is no reason to leave the formatter call in place for
control-heavy TEXT.

## Future Notes

- Exp 202 still closes quote/payload reservation for safe strings. Do not retry
  that shape without new compiler/runtime evidence.
- `json_write_u00_escape` is now the baseline for unnamed control bytes. Future
  TEXT `selectBytes()` work should target a different mechanism: the SWAR escape
  scan, a measurable copy boundary, or production/profile evidence that TEXT
  cells dominate encoder wall.
- Keep using `benchmark/experiments/select_bytes_text_string_reserve.dart` for
  TEXT JSON encoder work. The control row is the decision gate for `\u00XX`
  emission; safe ASCII and named-escape rows are guards.

## Validation

- `dart pub get`
- `dart format benchmark/experiments/select_bytes_text_string_reserve.dart`
- `dart analyze --fatal-infos native/resqlite.c
  benchmark/experiments/select_bytes_text_string_reserve.dart
  test/database_test.dart`
- `dart test test/database_test.dart --name selectBytes`
- Focused order-flipped A/B with
  `benchmark/experiments/select_bytes_text_string_reserve.dart`
