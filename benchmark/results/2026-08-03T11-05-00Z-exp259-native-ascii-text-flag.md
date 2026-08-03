# Experiment 259: native TEXT ASCII classification

Collected 2026-08-03 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `dedd80a`; candidate is the same tree plus the
`RESQLITE_TEXT_ASCII` classification. Both arms were built as native-asset-aware
AOT CLI bundles so the decode path is AOT-compiled (exp 193's requirement for
any `Row`/decode change):

```console
dart build cli --target=bin/select_rows_text_decode.dart --output=<arm>
<arm>/bundle/bin/select_rows_text_decode --warmup=10 --samples=31
```

The harness source is
[`benchmark/experiments/select_rows_text_decode.dart`](../experiments/select_rows_text_decode.dart);
`bin/` is only where `dart build cli` requires the entry point to live.

Each arm run is a fresh process; each lane seeds its own database, warms up 10
selects, and then times 31 `db.select('SELECT * FROM items')` calls. Pass 1
collects baseline first, pass 2 collects candidate first (order-flipped
confirmation per `JOURNAL.md`). Values are microseconds.

## Lanes

| lane | shape | role |
|---|---|---|
| `text8-short` | 10k rows x 8 ASCII TEXT, 10 B/cell | primary — the common short-value shape, and the one where the Dart scan misses its word-at-a-time path |
| `text8-mid` | 10k x 8 ASCII TEXT, 40 B/cell | confirmation |
| `text4-long` | 2k x 4 ASCII TEXT, 400 B/cell | confirmation — scan-length scaling |
| `text8-cjk` | 10k x 8 CJK TEXT, ~36 B/cell | guard — non-ASCII still pays `utf8.decode`, and the native scan no longer bails at the first high byte |
| `mixed6` | 10k x 6 mixed (4 TEXT + REAL) | default product row shape |
| `int8` | 10k x 8 INTEGER | control — no TEXT, so both arms run byte-identical code |

## Results

| lane | pass | baseline p50 | candidate p50 | Δ p50 | baseline p90 | candidate p90 | Δ p90 |
|---|---|---:|---:|---:|---:|---:|---:|
| text8-short | 1 | 6007 | 5266 | -12.3% | 6674 | 5805 | -13.0% |
| text8-short | 2 | 5915 | 5297 | -10.4% | 6431 | 5696 | -11.4% |
| text8-mid | 1 | 6783 | 5813 | -14.3% | 7554 | 6352 | -15.9% |
| text8-mid | 2 | 6501 | 5806 | -10.7% | 6841 | 6556 | -4.2% |
| text4-long | 1 | 837 | 651 | -22.2% | 1714 | 1470 | -14.2% |
| text4-long | 2 | 818 | 659 | -19.4% | 1735 | 1506 | -13.2% |
| text8-cjk | 1 | 12491 | 12193 | -2.4% | 13598 | 12764 | -6.1% |
| text8-cjk | 2 | 12326 | 12117 | -1.7% | 13285 | 12455 | -6.2% |
| mixed6 | 1 | 3927 | 3620 | -7.8% | 5020 | 4163 | -17.1% |
| mixed6 | 2 | 3865 | 3562 | -7.8% | 5418 | 4497 | -17.0% |
| int8 | 1 | 2772 | 2777 | +0.2% | 2884 | 2843 | -1.4% |
| int8 | 2 | 2756 | 2675 | -2.9% | 2846 | 2805 | -1.4% |

## Drift classification

`dart run benchmark/ab_drift_check.dart --input=<pairs>.json --markdown` over the
per-run values above:

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV |
|---|---|---:|---:|---:|
| text8-short | REPRODUCED (real effect) | -12.3% | -10.4% | 11.0% |
| text8-mid | REPRODUCED (real effect) | -14.3% | -10.7% | 8.8% |
| text4-long | REPRODUCED (real effect) | -22.2% | -19.4% | 50.0% |
| text8-cjk | inconclusive / neutral | -2.4% | -1.7% | 6.8% |
| mixed6 | REPRODUCED (real effect) | -7.8% | -7.8% | 18.7% |
| int8 | inconclusive / neutral | +0.2% | -2.9% | 2.1% |

The `int8` control is the load-bearing one: it contains no TEXT, so both binaries
run identical code there. It moves +0.2% then -2.9% — opposite signs, both inside
the 3% effect floor — which is what rules out the systematic per-worktree binary
offset exp 254 hit. `text4-long`'s 50% CV comes from its much shorter absolute
lane time (~0.7 ms), where a single scheduling outlier dominates the spread; its
p50 and p90 both move the same direction in both passes.

## Mechanism probe (scratch, not committed)

A standalone AOT microbenchmark over `malloc`'d 8-aligned ASCII payloads compared
the shipped `fastDecodeText` against a direct `String.fromCharCodes` on the same
pointer (i.e. what the decoder does once the native step loop has already
answered "is this ASCII?"). Two runs:

| payload | scan-in-Dart | pre-flagged | Δ |
|---|---:|---:|---:|
| 6-14 B | 20.8 / 17.5 ns/cell | 18.3 / 11.7 ns/cell | -12% / -34% |
| 20-40 B | 25.1 / 20.0 ns/cell | 16.0 / 12.2 ns/cell | -36% / -39% |
| 200 B | 36.6 / 32.2 ns/cell | 18.5 / 16.8 ns/cell | -49% / -48% |

That is the size of the hole the classification moves out of Dart: 6-15 ns per
TEXT cell, which at 80k cells per `text8-*` lane is 0.5-1.2 ms — the right order
of magnitude for the end-to-end deltas above.
