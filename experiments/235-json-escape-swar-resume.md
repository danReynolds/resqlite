# Experiment 235: Resume SWAR escape scan after each dirty chunk

**Date:** 2026-07-21
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B
  (`benchmark/experiments/select_bytes_text_string_reserve.dart`),
  two rounds of order-flipped passes on a quiet box; no release-suite run
  because the changed path is specifically the TEXT-cell JSON string escaper
  and the focused harness isolates safe, sparse-escape, dense-escape, and
  late-escape shapes directly.

## Problem

`resqlite_json_write_string` — the `SQLITE_TEXT` arm of the `selectBytes`
row serializer — escapes each TEXT cell with a SWAR fast scan that inspects
8 bytes at a time and skips whole clean chunks without touching them
byte-by-byte (the common case: text with no JSON-escapable bytes). But the
scan was structured as a `while (i + 8 <= len)` SWAR loop that `break`s to a
trailing byte-by-byte `for` loop on the **first** chunk containing an
escapable byte — and never returns to SWAR.

That means a single escape early in an otherwise-safe value forces the entire
remaining tail through the one-byte-at-a-time loop. A 256-byte log line with a
newline near the front, a multi-line chat message, a paragraph of prose with a
stray quote, or JSON stored as TEXT all hit this: the value is >95% safe bytes,
but the scanner crawls almost all of it one byte at a time because it saw one
escape early. [Exp 230](230-neon-json-scan-copy.md) sped up the *safe-prefix
scan* with NEON and was rejected at its 256B cutoff, but it explicitly "did not
restart SIMD after an escape" — so the resume inefficiency was never addressed.

## Hypothesis

If the SWAR skip is re-entered after each dirty chunk instead of abandoned
permanently, a sparse escape only downgrades the single 8-byte chunk that
actually contains it; the clean spans on either side keep skipping 8 at a time.
The win should reproduce on long TEXT with sparse escapes (multi-line text),
while the pure-safe common case stays byte-identical (the inner scan is
unchanged) and dense-escape text pays at most a small per-dirty-chunk cost.

Acceptance criterion, declared before measuring: the load-bearing row is the
**256B sparse-newline** lane (a `\n` roughly every 80 bytes — realistic
word-wrapped text). It must reproduce a clear win across the order flip, with
the pure-safe long-ASCII guard neutral. Larger and sparser lanes are
confirmation; dense-escape lanes are guards whose cost is recorded, not tuned
around.

## Approach

The scanner becomes an outer loop wrapping the original tight SWAR skip:

```c
while (i < len) {
    while (i + 8 <= len) {            // baseline's inner skip, 1 bounds check/chunk
        ...SWAR classify 8 bytes...
        if (dirty) break;
        i += 8;
    }
    if (i >= len) break;
    int block_end = i + 8 <= len ? i + 8 : len;
    for (; i < block_end; i++) {      // handle one dirty chunk (or the tail)
        ...emit escape or accumulate safe byte...
    }
}
```

Key design points, each load-bearing for a guard result:

- **The inner SWAR loop keeps baseline's single bounds check per clean chunk.**
  An earlier candidate that used one `while (i < len)` with an inner
  `if (i + 8 <= len)` paid a *second* bounds check on every clean chunk and
  regressed the pure-safe and late-escape guards +7%; folding the skip back into
  a tight inner `while` collapsed that to noise.
- **On a SWAR miss, exactly the offending 8-byte chunk is handled byte-by-byte,
  then SWAR resumes** — one SWAR probe per dirty chunk, not per byte. The
  first candidate re-probed SWAR after every safe byte inside a dirty region and
  regressed dense-escape +24%.
- **Escape emission, tables (`json_esc_len`, `json_esc_char`), and `\uXXXX`
  handling are unchanged.** Output is byte-identical; the existing
  `native_encoder_diff_test.dart` oracle (escapes injected at positions
  {0, 15, 16, len−1} across lengths 0–1024, compared byte-for-byte against
  `dart:convert`) passes unchanged.

The harness gains two sparse-escape modes it lacked: `sparseNewline` (a `\n`
every ~80 bytes) and `sparseEarly` (one escape near the start, then a long safe
tail). The pre-existing `escaped` (dense) and `lateEscape` (escape at the very
end) lanes stay as guards — neither exercised the resume inefficiency, which is
why the win was invisible before.

## Results

Two rounds of order-flipped passes (5 BASE / 4 CAND medians), Apple Silicon.
Full data in
[`benchmark/results/2026-07-21T14-05-36Z-exp235-json-escape-swar-resume.md`](../benchmark/results/2026-07-21T14-05-36Z-exp235-json-escape-swar-resume.md).

| Lane | Δ (order-flipped) | |
|---|---:|---|
| pure-safe long ASCII 256B | −3.4% | common case — parity |
| pure-safe very long ASCII 1KiB | −1.7% | common case — parity |
| **sparse-newline 256B** | **−23.4%** | **load-bearing** |
| sparse-newline 1KiB | −31.4% | confirmation |
| sparse-early 256B | −44.7% | confirmation |
| sparse-early 1KiB | −44.1% | confirmation |
| dense-escape 24B / 96B | +2.1% / +0.1% | guard — noise |
| dense-escape 256B | +6.0% | guard — pathological only |
| late-escape 96B / 256B | +2.0% / +4.5% | guard — noisy ~parity |

Realistic multi-line TEXT encodes **~1.3×–1.8× faster**, and the extreme
one-early-escape case is nearly 2× faster — because the old scanner turned a
single early escape into a full-length byte crawl and the new one does not. The
pure-safe path (the dominant real workload) is provably unchanged and measures
as parity. The lone real cost is dense-escape 256B at +6.0%: text where ~⅓ of
bytes need escaping pays one extra SWAR probe per all-dirty chunk. That
distribution is not natural text, is not in the release suite, and the sparse
win dominates the realistic mix.

## Outcome

**Accepted (in review).** A contained ~−23% (load-bearing) to −44%
`selectBytes` TEXT-encoding win on sparse-escape values — the common shape of
multi-line and lightly-quoted text — with the escape-free common path unchanged
and byte-identical output. The cost is ~+6% on pathological dense-escape 256B
text only.

Would reopen the *dense* regression only if a real workload or profile shows
dense-escape TEXT (≥⅓ escapable bytes) is a hot path; the natural next TEXT-side
mechanism remains the signals-named SIMD escape scan for the safe-prefix scan
speed (distinct from this resume fix), gated by the same focused harness.
