# Exp 204: UTF-8 over-reserve bind prototype

Prototype archived at `archive/exp-204`. Final branch reverts the runtime
change and keeps this result record plus the experiment writeup.

## Candidate

The prototype changed single-row `allocateParams` sizing for the first
non-ASCII code unit in a string:

- baseline: call `_utf8Length(value)` to compute the exact payload byte count,
  then run `_writeUtf8(value, ...)` to write bytes
- candidate: reserve `ascii_prefix + 3 * remaining_utf16_code_units`, then run
  `_writeUtf8(value, ...)` and record the actual byte count

This removes the exact length scan for CJK-like large strings, but can reserve
more bytes than needed for two-byte text, surrogate-heavy text, or a mostly
ASCII string with one non-ASCII code unit.

## Focused end-to-end bind workload

Command:

```text
dart run benchmark/experiments/single_row_large_text_bind.dart
```

Rows below are median ms / 100 `INSERT INTO doc(body) VALUES (?)` writes.

### Pair 1: candidate first, baseline second

| Payload | Candidate | Baseline | Delta |
|---|---:|---:|---:|
| ASCII 1 KB | 4.69 | 5.00 | -6.2% |
| ASCII 16 KB | 9.03 | 9.24 | -2.3% |
| ASCII 64 KB | 26.06 | 23.54 | +10.7% |
| ASCII 256 KB | 92.35 | 88.15 | +4.8% |
| ASCII 1 MB | 354.59 | 341.27 | +3.9% |
| CJK 1 KB | 2.38 | 3.40 | -30.0% |
| CJK 16 KB | 7.08 | 7.68 | -7.8% |
| CJK 64 KB | 23.30 | 26.05 | -10.6% |
| CJK 256 KB | 86.60 | 93.57 | -7.4% |
| CJK 1 MB | 315.00 | 355.81 | -11.5% |

### Pair 2: baseline first, candidate second

| Payload | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| ASCII 1 KB | 4.18 | 4.25 | +1.7% |
| ASCII 16 KB | 8.70 | 8.79 | +1.0% |
| ASCII 64 KB | 23.21 | 23.92 | +3.1% |
| ASCII 256 KB | 86.20 | 86.33 | +0.2% |
| ASCII 1 MB | 331.26 | 335.76 | +1.4% |
| CJK 1 KB | 2.02 | 2.17 | +7.4% |
| CJK 16 KB | 6.96 | 7.28 | +4.6% |
| CJK 64 KB | 24.46 | 22.96 | -6.1% |
| CJK 256 KB | 90.63 | 81.50 | -10.1% |
| CJK 1 MB | 340.76 | 306.91 | -9.9% |

The CJK 64 KB through 1 MB rows move candidate-faster in both orders. The 1 KB
and 16 KB CJK rows do not reproduce. ASCII is logically unchanged by the
prototype, but it is still the critical guard for this bind harness; it stays
mostly neutral in the cleaner pair and had one noisy +10.7% 64 KB flag in the
candidate-first pair.

## Encoder micro

Command:

```text
dart run benchmark/experiments/single_row_param_packing.dart
```

Rows are median ns/op over 200,000 allocate/free cycles per sample.

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| ascii-1-short | 37.4 | 38.1 | +1.9% |
| ascii-5-mixed | 102.3 | 102.8 | +0.5% |
| ascii-1-large | 1362.4 | 1361.2 | -0.1% |
| unicode-1 | 296.5 | 236.2 | -20.3% |
| blob-int | 43.2 | 45.8 | +6.0% |

The micro confirms that skipping the exact length pass removes real encoder
work for non-ASCII text. The end-to-end decision still rejects the runtime
prototype because the allocation policy is too broad for mixed Unicode text.
