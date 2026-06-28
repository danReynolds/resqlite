# Experiment 202: TEXT string reservation for selectBytes

**Date:** 2026-06-28T06:09:38-04:00
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused `benchmark/experiments/select_bytes_text_string_reserve.dart`, order-flipped pair
**Archive:** [`archive/exp-202`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-202)

## Problem

After [exp 199](199-row-level-buf-ensure.md), fixed-size NULL / INTEGER /
FLOAT cells in `write_json_to_buf` write directly under one row-level
reservation. Variable-size TEXT and BLOB cells still call helper functions
because their encoded length depends on the value.

The TEXT helper, `json_write_string`, had a small remaining common-case framing
cost on strings that need no JSON escaping:

```c
buf_write_char(b, '"');
... scan/copy string bytes ...
buf_write_char(b, '"');
```

For TEXT-heavy `selectBytes()` payloads, those quote writes and capacity checks
could plausibly be part of the remaining variable-cell overhead. The candidate
was deliberately narrow and behavior-preserving: change only how the existing
safe-string output is reserved and copied, not the escape rules or UTF-8 bytes.

## Hypothesis

Reserving `len + 2` once at the start of `json_write_string` should let the
common no-escape case write the opening quote, payload, and closing quote
directly into `json_buf`. Escaped strings can keep the existing grow-as-needed
path after the first escape.

The acceptance bar was the TEXT-focused harness: safe ASCII lanes should
reproduce candidate-faster across an order-flipped pair, while escaped, mixed,
and narrow lanes should stay neutral.

## Approach

The archived prototype changed only `native/resqlite.c`:

- call `buf_ensure(b, len + 2)` before writing the opening quote,
- write the opening quote directly to `b->data + b->len`,
- track whether an escaped byte was seen,
- for no-escape strings, copy the remaining span and closing quote directly,
- for escaped strings, keep the existing `buf_write` fallback for spans, escape
  sequences, and the closing quote.

The experiment also adds
`benchmark/experiments/select_bytes_text_string_reserve.dart`, a focused harness
with short safe ASCII, wider safe ASCII, medium safe ASCII, escaped text, mixed
TEXT / INTEGER / REAL, and narrow small-rowset guards.

The runtime prototype is archived at `archive/exp-202` and reverted from this
branch. No runtime code is kept.

## Results

Focused harness:
`dart run benchmark/experiments/select_bytes_text_string_reserve.dart`.
Values are median microseconds per `selectBytes()` query.

| Lane | Baseline P1 | Candidate P1 | Delta P1 | Baseline P2 | Candidate P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 short ASCII text | 2943 | 2964 | +0.7% | 3043 | 3020 | -0.8% |
| 10k rows x 20 short ASCII text | 6724 | 6668 | -0.8% | 6888 | 6890 | +0.0% |
| 10k rows x 8 medium ASCII text | 3995 | 3949 | -1.2% | 4065 | 4036 | -0.7% |
| 10k rows x 8 escaped text | 7113 | 7034 | -1.1% | 7203 | 7080 | -1.7% |
| 10k rows x 8 mixed (4 text + 2 int + 2 real) | 5432 | 5347 | -1.6% | 5533 | 5467 | -1.2% |
| 1k rows x 2 short ASCII text | 113 | 112 | -0.9% | 115 | 117 | +1.7% |

Focused correctness against the archived prototype:

```bash
dart test test/database_test.dart --name selectBytes
```

All 9 selected tests passed, including JSON special characters,
embedded-NUL text, `jsonEncode(select())` equivalence, int64 extremes,
integer-valued REALs, and BLOB base64.

## Decision

Rejected. The candidate did not produce a decision-grade TEXT win. Safe-string
lanes stayed within roughly +/-2% and the narrow guard changed sign. The escaped
and mixed lanes trended slightly faster, but they are not the load-bearing
mechanism for a no-escape direct-copy optimization and the magnitude is still
below the current bar.

No runtime code is kept. The focused harness remains because it closes this
specific helper-call reservation candidate and gives future TEXT JSON encoder
work a direct gate.

## Future Notes

- Do not retry `json_write_string` quote/payload reservation without a new
  compiler/runtime fact; the safe ASCII lanes did not reproduce a material win.
- Future TEXT `selectBytes()` work should target the SWAR escape scan, escaped
  control-character formatting, a measurable allocation/copy boundary, or a
  production profile showing TEXT cells dominate the encoder wall.
- Use `benchmark/experiments/select_bytes_text_string_reserve.dart` before
  accepting or rejecting the next TEXT JSON encoder candidate. A real win should
  move the safe ASCII lanes and keep escaped/mixed guards neutral or better.
