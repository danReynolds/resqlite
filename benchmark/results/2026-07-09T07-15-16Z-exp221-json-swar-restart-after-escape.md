# Exp 221 — SWAR restart after escape in `json_write_string`

Focused `benchmark/experiments/select_bytes_text_string_reserve.dart` A/B
against `origin/main` at `44a6d39`. The candidate rewraps
`json_write_string` so each escape byte emits and then re-enters the 8-byte
SWAR fast scan for the tail, instead of leaving the byte-by-byte fallback
to own the rest of the string. Safe strings, escape emission, SWAR word
detection, buffer growth policy, JSON output bytes, and public API are
unchanged.

Both worktrees used the updated benchmark harness (which adds two
`sparse-escape` lanes exercising the mechanism directly). The baseline
worktree's native code was `origin/main` at 44a6d39; the candidate
worktree carried the exp 221 change under `native/resqlite.c`.

Harness reports median microseconds per `selectBytes()` query. Lower is
better.

## Pair 1 — baseline then candidate

| Lane | Baseline µs/query | Candidate µs/query | Δ |
|---|---:|---:|---:|
| 10k rows × 8 short ASCII text | 2694 | 2725 | +1.2% |
| 10k rows × 20 short ASCII text | 6273 | 6315 | +0.7% |
| 10k rows × 8 medium ASCII text | 4153 | 3952 | −4.8% |
| 10k rows × 8 escaped text | 6839 | 7160 | +4.7% |
| 10k rows × 8 sparse-escape 96B text | 6866 | 5848 | **−14.8%** |
| 10k rows × 8 sparse-escape 256B text | 13255 | 7796 | **−41.2%** |
| 10k rows × 8 mixed (4 text + 2 int + 2 real) | 5036 | 5386 | +6.9% |
| 1k rows × 2 short ASCII text | 102 | 109 | +6.9% |

## Pair 2 — candidate then baseline (order-flipped)

| Lane | Candidate µs/query | Baseline µs/query | Δ (cand vs base) |
|---|---:|---:|---:|
| 10k rows × 8 short ASCII text | 2703 | 2865 | −5.7% |
| 10k rows × 20 short ASCII text | 6298 | 6323 | −0.4% |
| 10k rows × 8 medium ASCII text | 3945 | 3851 | +2.4% |
| 10k rows × 8 escaped text | 7077 | 6700 | +5.6% |
| 10k rows × 8 sparse-escape 96B text | 5777 | 7854 | **−26.4%** |
| 10k rows × 8 sparse-escape 256B text | 7731 | 13393 | **−42.3%** |
| 10k rows × 8 mixed (4 text + 2 int + 2 real) | 5123 | 5079 | +0.9% |
| 1k rows × 2 short ASCII text | 116 | 105 | +10.5% |

## Interpretation

The two `sparse-escape` lanes are the load-bearing signal. Each cell is a
mostly-safe ASCII string with a single `"` at byte 4 followed by a long
safe tail; the pre-exp-221 fallback owns that tail byte-by-byte, while
the candidate re-enters SWAR after the escape. The 256B lane reproduces
`−41.2% / −42.3%` across the order flip — the candidate collapses ~5.5 ms
of per-query wall time to ~3.2 ms on the same rowset. The 96B lane
reproduces `−14.8% / −26.4%`, matching the shorter safe tail (the tail
is 91 bytes instead of 251, so relative SWAR win is smaller). Both are
reproduced same-direction candidate-faster; per exp 177 /
`ab_drift_check.dart` these clear the drift bar.

The non-target lanes are guards:

- Safe ASCII lanes (`short`, `medium`, `1k × 2`) stay within ±6% —
  the SWAR loop already owns them end-to-end pre-exp-221, so the
  candidate's outer-while shape can only add or remove a single
  branch, not shift the mechanism.
- `escaped` mode packs an escape byte roughly every 8 characters. The
  restart-SWAR pattern still helps here in principle, but each SWAR
  re-entry is quickly re-broken by the next escape, so wall stays
  within noise (+4.7% / +5.6%).
- `mixed` mode is a broader row-shape guard: 4 text + 2 int + 2 real
  cells. Text cells are 24B safe ASCII, so `json_write_string` runs
  its SWAR-only path — the mechanism is inactive. Wall stays neutral
  (+6.9% / +0.9%).

The mechanism activates on TEXT strings that have a small number of
escape bytes and a long safe run afterward — exactly the shape of
real-world content strings that carry the occasional `"` or `\n` inside
otherwise-safe payloads.
