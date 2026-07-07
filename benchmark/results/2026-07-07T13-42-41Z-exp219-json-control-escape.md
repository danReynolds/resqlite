# Exp 219 - Direct JSON control-character escapes for selectBytes TEXT

Focused `benchmark/experiments/select_bytes_text_string_reserve.dart` A/B
against `origin/main` at `e45b038`. Candidate replaces the
`snprintf("\\u%04x")` path inside `json_write_string` with direct `\u00XX`
byte emission for control characters that do not have a named JSON escape.
Safe strings, named escapes, SWAR scanning, buffer growth policy, JSON output,
and public API are unchanged.

The baseline worktree used the updated benchmark harness only; its native code
remained `origin/main`.

Harness reports median microseconds per `selectBytes()` query. Lower is better.

## Pair 1 - baseline then candidate

| Lane | Baseline us/query | Candidate us/query | Delta |
|---|---:|---:|---:|
| 10k rows x 8 short ASCII text | 3019 | 2957 | -2.1% |
| 10k rows x 20 short ASCII text | 7120 | 6280 | -11.8% |
| 10k rows x 8 medium ASCII text | 6811 | 4055 | -40.5% |
| 10k rows x 8 escaped text | 7346 | 7090 | -3.5% |
| 10k rows x 8 control text | 35927 | 6371 | -82.3% |
| 10k rows x 8 mixed (4 text + 2 int + 2 real) | 5562 | 5421 | -2.5% |
| 1k rows x 2 short ASCII text | 132 | 115 | -12.9% |

## Pair 2 - candidate then baseline

| Lane | Baseline us/query | Candidate us/query | Delta |
|---|---:|---:|---:|
| 10k rows x 8 short ASCII text | 3005 | 2906 | -3.3% |
| 10k rows x 20 short ASCII text | 7113 | 6450 | -9.3% |
| 10k rows x 8 medium ASCII text | 3990 | 5594 | +40.2% |
| 10k rows x 8 escaped text | 7464 | 7855 | +5.2% |
| 10k rows x 8 control text | 35824 | 6370 | -82.2% |
| 10k rows x 8 mixed (4 text + 2 int + 2 real) | 7253 | 5588 | -23.0% |
| 1k rows x 2 short ASCII text | 127 | 112 | -11.8% |

## Interpretation

The target control-character lane reproduced the candidate win across the order
flip: `35927 -> 6371 us/query` and `35824 -> 6370 us/query`, both about
`-82%`. That is the exact path changed by the candidate: non-named control
bytes such as `0x01`, `0x02`, and `0x03` no longer format through `snprintf`.

The non-target lanes are not load-bearing for this experiment. Safe ASCII and
named-escape rows do not use the changed formatter. They stayed noisy in the
same way exp 202's TEXT harness has before: medium ASCII flipped direction
between pairs, escaped text stayed within a few percent, and mixed/narrow rows
moved with run noise rather than mechanism. There is no reproduced regression
on a mechanically touched guard.

The result clears the bounded merge bar for control-character TEXT payloads:
the implementation is tiny, byte-for-byte compatible, and removes an expensive
stdio formatter from a hot helper without changing the common safe-string path.
