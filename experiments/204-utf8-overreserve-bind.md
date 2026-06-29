# Experiment 204: UTF-8 over-reserve bind sizing

**Date:** 2026-06-29
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** Focused `single_row_large_text_bind.dart` order-flipped
  pairs plus `single_row_param_packing.dart` micro; see Results.
**Archive:** [`archive/exp-204`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-204)

## Problem

Exp 187 removed the temporary `utf8.encode()` list from non-ASCII single-row
binds by sizing strings with `_utf8Length`, then writing them directly into the
native parameter buffer with `_writeUtf8`. That was the right broad default: it
kept exact allocation size and improved large CJK binds by roughly 31-39%.

One cost remains. Large non-ASCII strings are scanned twice: once to compute the
exact UTF-8 byte length and once to write the bytes. For CJK-shaped text, where
each code unit is normally three UTF-8 bytes, an exact length prepass looks
avoidable. The writer pass already computes the actual byte count as it writes,
so a candidate can reserve a safe upper bound and record the exact length after
the write.

## Hypothesis

For large CJK single-row text binds, reserve
`ascii_prefix + 3 * remaining_utf16_code_units` after the first non-ASCII code
unit instead of calling `_utf8Length(value)`. This should remove one full string
scan from the CJK path while preserving SQLite bind semantics because
`text.len` still records the exact number of bytes written by `_writeUtf8`.

The risk is allocation policy, not correctness. The upper bound is exact for
pure three-byte CJK text, but it can over-reserve for two-byte scripts,
surrogate pairs, or mostly ASCII text containing one non-ASCII code unit.

## Approach

The archived prototype changes only `allocateParams` in
`lib/src/native/resqlite_bindings.dart`:

- ASCII-only parameter lists keep the exp 186 direct ASCII path.
- When a string's sizing scan finds the first non-ASCII code unit, the
  prototype reserves a safe upper bound via a non-inlined helper instead of
  scanning the whole string with `_utf8Length`.
- The write pass is unchanged: `_writeUtf8` emits the bytes and the struct's
  `text.len` field receives the exact byte count actually written.

No public API changes and no SQLite binding semantics change. The prototype is
preserved at `archive/exp-204`; the final branch reverts the runtime change.

## Results

Raw focused tables are preserved in
[`benchmark/results/2026-06-29T10-11-24Z-exp204-utf8-overreserve-bind.md`](../benchmark/results/2026-06-29T10-11-24Z-exp204-utf8-overreserve-bind.md).

### Focused end-to-end bind workload

`single_row_large_text_bind.dart` reports median ms per 100 single-row inserts.

| Payload | Pair 1 delta | Pair 2 delta | Read |
|---|---:|---:|---|
| ASCII 64 KB | +10.7% | +3.1% | guard not cleaner than neutral |
| ASCII 256 KB | +4.8% | +0.2% | neutral to slightly slower |
| ASCII 1 MB | +3.9% | +1.4% | neutral to slightly slower |
| CJK 64 KB | -10.6% | -6.1% | reproduced candidate-faster |
| CJK 256 KB | -7.4% | -10.1% | reproduced candidate-faster |
| CJK 1 MB | -11.5% | -9.9% | reproduced candidate-faster |

The intended signal exists: CJK payloads at 64 KB through 1 MB move
candidate-faster in both orderings. The smaller CJK rows do not reproduce
cleanly (1 KB and 16 KB flipped sign in the baseline-first pass), which is fine
because the optimization is only plausible once payload size dominates the
writer round-trip.

The ASCII rows are logically unchanged by the prototype, but they remain the
important guard because exp 186 made large ASCII text a first-class workload.
They were neutral in the cleaner baseline-first pair and had one noisy 64 KB
candidate-first regression. That is not a decisive ASCII regression by itself,
but it is not evidence for shipping a broader allocation tradeoff either.

### Encoder micro

`single_row_param_packing.dart` isolates allocate/free cost:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| ascii-1-short | 37.4 ns/op | 38.1 ns/op | +1.9% |
| ascii-5-mixed | 102.3 ns/op | 102.8 ns/op | +0.5% |
| ascii-1-large | 1362.4 ns/op | 1361.2 ns/op | -0.1% |
| unicode-1 | 296.5 ns/op | 236.2 ns/op | -20.3% |
| blob-int | 43.2 ns/op | 45.8 ns/op | +6.0% |

The micro confirms that the exact length prepass is real work for non-ASCII
strings. It also confirms that the final helper-shaped prototype restored the
large ASCII micro guard after an earlier inline-arithmetic variant disturbed
the hot function body.

## Decision

**Rejected.** The CJK-large win is real enough to keep as evidence, but the
general-purpose runtime policy is not disciplined enough to merge.

The problem is the upper bound: after the first non-ASCII code unit, the
prototype reserves three bytes for every remaining UTF-16 code unit. That is
exact for pure CJK, but it can inflate the native bind buffer for two-byte
Latin/Greek/Cyrillic text, surrogate-heavy emoji text, and mixed strings such as
one accented character followed by mostly ASCII. Since `allocateParams` is a
public hot path and the existing exp 187 implementation already delivers the
large Unicode win with exact sizing, trading exact allocation for a CJK-shaped
special case is too broad.

Do not keep the runtime change. Reopen this only if a future candidate avoids
the exact prepass without broad over-reservation, or if a production profile
proves a known CJK-only large-text workload where the allocation tradeoff is
acceptable and separately guarded.

## Future Notes

- The rejected prototype is preserved at `archive/exp-204`.
- Future single-row Unicode bind work should run `single_row_large_text_bind.dart`
  and should add an explicit mixed-Unicode guard before accepting any allocation
  upper-bound strategy.
- If the next candidate wants this win, it should be more precise than
  "three bytes for the rest of the string" - for example, a bounded classifier
  with a measured mixed-text guard, or a writer that can size and emit without
  paying for two complete scans.
