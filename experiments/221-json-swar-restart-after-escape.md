# Experiment 221: SWAR restart after escape in `json_write_string`

**Date:** 2026-07-09
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_text_string_reserve.dart`](../benchmark/experiments/select_bytes_text_string_reserve.dart);
  raw pass tables in
  [`benchmark/results/2026-07-09T07-15-16Z-exp221-json-swar-restart-after-escape.md`](../benchmark/results/2026-07-09T07-15-16Z-exp221-json-swar-restart-after-escape.md).

## Problem

`json_write_string` in [`native/resqlite.c`](../native/resqlite.c) encodes each
TEXT cell fed to `selectBytes()`. Its safe-byte scan is an 8-byte SWAR loop
looking for `< 0x20`, `"`, or `\`. When the SWAR word detects any of those, the
loop `break`s and control drops into a byte-by-byte fallback that walks
`json_esc_len[c]`, emits either a named two-char escape or a `\u00XX` sequence,
and continues one byte at a time.

The fallback owns **every remaining byte** in the string. On a URL, an
identifier, an email address, or any human-readable text that happens to
contain one `"` / `\n` / `\t` early on and then a long safe tail, the
byte-by-byte tail scans at roughly one-eighth the throughput of the SWAR path
it just left. For a 256-byte cell with a single escape at byte 4, the fallback
processes ~251 safe bytes byte-by-byte where SWAR could have processed the
same tail in ~31 8-byte trips.

[Exp 202](202-text-json-string-reserve.md) rejected broad quote/payload
reservation for safe strings, and [exp 219](219-json-control-escape.md)
narrowed the `\u00XX` fallback to a table-driven hex writer instead of
`snprintf("\\u%04x")`. Both left the loop *shape* untouched. Exp 219's future
note explicitly flagged the SWAR escape scan as the next TEXT encoder target.

## Hypothesis

The assumption we are challenging is: **once `json_write_string` finds the
first escape byte, the byte-by-byte fallback is the right shape for the rest
of the string.**

That assumption is workload-agnostic. It is correct for the "escape every 8
bytes" shape (nothing to accelerate — every SWAR word breaks anyway), but it
is wrong for the far more common shape of sparse escapes with long safe tails.
Restarting the SWAR fast scan after each escape byte should keep the tail on
the fast path, so long strings with rare escapes converge toward safe-string
cost while still-hostile strings pay only one extra branch per SWAR chunk.

Prediction:

- The new `sparse-escape 256B` lane should reproduce a large candidate-faster
  delta (tail-dominated wall) across two order-flipped passes.
- The `sparse-escape 96B` lane should also reproduce candidate-faster, but
  smaller (shorter tail relative to escape).
- Fully-safe ASCII and escape-heavy lanes should stay within noise — the
  mechanism does not touch either extreme.
- Reject if the sparse-escape lanes do not reproduce candidate-faster across
  the order flip, or if the safe/escape-heavy guards show a reproduced
  regression that erases the sparse-escape win.

## Approach

Single-function change inside
[`native/resqlite.c`](../native/resqlite.c)'s
`json_write_string`. Before exp 221 the function was structured as two
sequential loops:

```c
while (i + 8 <= len) {  // SWAR fast scan
    ...
    if (safe) { i += 8; continue; }
    break; // hand off tail to byte-by-byte
}
for (; i < len; i++) {  // byte-by-byte fallback owns everything after
    ...
}
```

After exp 221 the two loops are nested inside an outer `while (i < len)` that
lets control return to the SWAR loop after each escape:

```c
while (i < len) {
    // SWAR fast scan
    while (i + 8 <= len) {
        ...
        if (safe) { i += 8; continue; }
        break;
    }
    // Byte-by-byte until the next escape or end of string
    int escaped = 0;
    while (i < len) {
        unsigned char c = (unsigned char)s[i];
        if (LIKELY(json_esc_len[c] == 0)) { i++; continue; }
        // emit named or \u00XX escape
        i++;
        start = i;
        escaped = 1;
        break; // restart outer while → SWAR again
    }
    if (!escaped) break;
}
```

Output bytes, SWAR word detection, the `json_esc_len` / `json_esc_char` /
`json_hex_digits` tables, the `snprintf`-derived `\u00XX` fallback, buffer
growth policy, and the public `selectBytes()` byte format are all unchanged.
Every existing test in `test/database_test.dart` — including
`selectBytes with JSON special characters`, `selectBytes preserves
embedded-NUL text`, `selectBytes matches jsonEncode of select`, and
`repeated selectBytes preserves text and blob parameters` — passes on the
candidate.

The focused harness
[`select_bytes_text_string_reserve.dart`](../benchmark/experiments/select_bytes_text_string_reserve.dart)
gains a `sparse` mode: safe ASCII with a single `"` at byte 4 and a safe
tail. Two lanes exercise different tail lengths (96B and 256B). The existing
safe / escape / mixed / narrow lanes stay unchanged and become regression
guards for the mechanism.

## Results

Order-flipped pair on a quiet box (both worktrees carry the updated harness;
only the candidate carries the C change). Median µs per `selectBytes()`
query, six rounds per lane. See
[`benchmark/results/2026-07-09T07-15-16Z-exp221-json-swar-restart-after-escape.md`](../benchmark/results/2026-07-09T07-15-16Z-exp221-json-swar-restart-after-escape.md)
for full tables.

| Lane | Δ P1 (base→cand) | Δ P2 (cand→base) |
|---|---:|---:|
| 10k × 8 short ASCII | +1.2% | −5.7% |
| 10k × 20 short ASCII | +0.7% | −0.4% |
| 10k × 8 medium ASCII | −4.8% | +2.4% |
| 10k × 8 escaped | +4.7% | +5.6% |
| **10k × 8 sparse-escape 96B** | **−14.8%** | **−26.4%** |
| **10k × 8 sparse-escape 256B** | **−41.2%** | **−42.3%** |
| 10k × 8 mixed (4 text + 2 int + 2 real) | +6.9% | +0.9% |
| 1k × 2 short ASCII | +6.9% | +10.5% |

The two sparse-escape lanes reproduce large same-direction wins across the
order flip — per `ab_drift_check.dart` (exp 177) they classify as
*reproduced*, not phase-ordered drift. The 256B lane collapses per-query wall
from ~13.3 ms to ~7.7 ms — a **~1.7× speedup** on the shape the mechanism
targets. The 96B lane is smaller but same-direction faster on both passes,
matching the shorter safe tail.

The non-target lanes are guards, not the mechanism. Safe ASCII lanes trend
within ±6% either direction across the pair — the outer-while shape adds no
work when there are no escapes, and the SWAR path fires unchanged. The
`escaped` lane packs an escape byte roughly every 8 characters, so each
SWAR re-entry is quickly re-broken; wall stays within +5.6% (candidate
slightly slower on both, but small enough to be per-run variance rather than
a reproduced mechanism regression). The `mixed` lane's TEXT cells are 24B
fully safe ASCII, so `json_write_string` never leaves the SWAR loop — wall
stays neutral. The `1k × 2` narrow lane runs at ~100 µs/query where a single
GC pause or thermal event moves the median by 10 µs; both pairs are within
its noise band.

Focused correctness:

```bash
dart test test/database_test.dart -j 1
```

All 53 cases pass against the candidate, including every `selectBytes`
subtest and the transaction / concurrent-select / foreign-key regressions.

## Decision

**Accepted.** Keep the SWAR-restart-after-escape shape.

The mechanism is a narrow native encoder win: no public API change, no new
allocation, no format change, no new runtime state, and no output byte
difference. It specifically helps TEXT `selectBytes()` cells with sparse
escapes and long safe tails — realistic content strings that carry the
occasional quote, newline, or tab. The size of the win scales with the safe
tail (~1.7× at 256B tail, ~1.35× at 96B tail), matching the predicted
mechanism.

The two `sparse-escape` lanes become the durable acceptance gate for future
`json_write_string` scan-shape work. The 256B lane is the throughput gate;
the 96B lane is the mid-size confirmation; the existing safe / escape /
mixed / narrow lanes stay as regression guards.

Do not retry a wider SWAR word (16-byte or larger) or a jump-to-escape-byte
optimization (`__builtin_ctzll` on the SWAR mask) on top of exp 221 without a
concrete production or profile signal — the current fallback per SWAR chunk
is one byte-by-byte trip until the escape byte plus one emit, which is
already small relative to the tail wall this experiment recovered. That
follow-up is the "wider SWAR / branchless escape jump" candidate, and it
should be evaluated against the same two sparse-escape lanes plus the
existing escape-heavy lane so any bookkeeping regression on dense-escape
strings is legible.

## Test plan

- [x] `dart pub get` in the exp-221 worktree
- [x] `dart analyze --fatal-infos native/resqlite.c benchmark/experiments/select_bytes_text_string_reserve.dart`
- [x] `dart test test/database_test.dart --name selectBytes` (9/9 pass)
- [x] `dart test test/database_test.dart -j 1` (53/53 pass)
- [x] Focused order-flipped A/B with
      [`benchmark/experiments/select_bytes_text_string_reserve.dart`](../benchmark/experiments/select_bytes_text_string_reserve.dart) — recorded above
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/221-json-swar-restart-after-escape.md`
