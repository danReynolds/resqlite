# exp 235 — resume SWAR escape scan after each dirty chunk

**Date:** 2026-07-21
**Harness:** `benchmark/experiments/select_bytes_text_string_reserve.dart`
**Hardware:** Apple Silicon (macOS ARM64)
**Baseline:** `origin/main` at `0af824f` (unmodified `native/resqlite_json.c`)
**Candidate:** `exp-235-json-escape-swar-resume`

The candidate restructures `resqlite_json_write_string`'s escape scanner so the
SWAR 8-byte fast-skip resumes after each dirty chunk, instead of breaking to the
byte-by-byte path permanently on the first escapable byte. The inner SWAR loop
keeps baseline's single bounds check per clean chunk; only a dirty 8-byte chunk
(or the final <8-byte tail) is handled byte-by-byte, after which the outer loop
re-enters the SWAR skip. Escape emission, tables, and output are byte-identical
(verified by the `native_encoder_diff_test.dart` dart:convert oracle).

## Decision gate

- Load-bearing acceptance row (declared before measuring): **sparse-newline
  256B** — realistic multi-line text with a `\n` roughly every 80 bytes. Accept
  only if it reproduces a clear win across the order flip.
- Common-case guard: pure-safe (escape-free) long ASCII must stay neutral — the
  scanner is unchanged on that path.
- Pathological guard: dense-escape lanes (~⅓ of bytes escapable) may pay a
  small per-dirty-chunk SWAR-probe cost; record it.

## Final medians (microseconds/query), 5 BASE / 4 CAND order-flipped passes

| Lane | BASE | CAND | Δ | note |
|---|---:|---:|---:|---|
| pure-safe long ASCII 256B | 7631 | 7370 | −3.4% | common case — parity (overlapping) |
| pure-safe very long ASCII 1KiB | 2465 | 2422 | −1.7% | common case — parity (overlapping) |
| **sparse-newline 256B** | 13209 | 10114 | **−23.4%** | **load-bearing — accept** |
| sparse-newline 1KiB | 4804 | 3294 | −31.4% | confirmation |
| sparse-early 256B | 13690 | 7565 | −44.7% | confirmation (worst case for old scanner) |
| sparse-early 1KiB | 4467 | 2498 | −44.1% | confirmation |
| dense-escape 24B | 7191 | 7340 | +2.1% | guard — within noise |
| dense-escape 96B | 20641 | 20662 | +0.1% | guard — parity |
| dense-escape 256B | 48729 | 51675 | +6.0% | guard — real, pathological only |
| late-escape 96B | 4508 | 4600 | +2.0% | guard — noisy ~parity |
| late-escape 256B | 7234 | 7560 | +4.5% | guard — noisy ~parity |

Raw samples (sorted) for the load-bearing and boundary lanes:

```
sparse-newline 256B : BASE [12688,13006,13209,13779,13901] / CAND [9929,10098,10131,10354]
sparse-early   256B : BASE [13401,13663,13690,13783,14356] / CAND [7161,7534,7596,7676]
pure-safe      1KiB : BASE [2243,2434,2465,2484,3001]      / CAND [2386,2388,2456,2617]
dense-escape   256B : BASE [48306,48441,48729,49040,49315] / CAND [50959,51311,52039,52171]
```

## Interpretation

Realistic multi-line TEXT — anything with a newline, an occasional quote, or a
tab inside an otherwise-safe body — encodes **~1.3× to ~1.8× faster**: the old
scanner abandoned the 8-byte SWAR skip forever on the first escape, so a single
`\n` near the start of a 256-byte value forced the whole tail through the
one-byte-at-a-time loop. Resuming the skip after the dirty chunk keeps the fast
path for the safe spans between escapes. The pure-safe common case is unchanged
(the inner loop is byte-identical), confirmed as parity.

The only real cost is on dense-escape text where roughly a third of bytes need
escaping (escaped binary, heavily-delimited content): +6.0% at 256B, from one
extra SWAR probe per all-dirty chunk. That distribution is not representative of
natural text and is not in the release suite; the realistic sparse-escape win
dominates. Both earlier candidate structures (retry-SWAR-per-byte, and a single
outer `while` with a double bounds check) regressed the safe and dense-24B
guards +7–9%; the tight-inner-loop structure collapses those back to noise while
keeping the sparse win.

## Outcome

Accepted (in review): a contained ~−23% (load-bearing) to −44% win on
sparse-escape TEXT `selectBytes` encoding, common-case safe path provably
unchanged, at the cost of ~+6% on pathological dense-escape 256B text. No API,
platform, or allocation change; pure portable C.
