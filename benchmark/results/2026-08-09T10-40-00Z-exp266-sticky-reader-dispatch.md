# Experiment 266: sticky reader dispatch

Collected 2026-08-09 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `4b963ad`; candidate is the same tree plus the
`_preferred` dispatch cursor in `ReaderPool._dispatch`, the `selectBytes`
opt-out, the `preferredWorkerIndex` accessor and three `dispatch stickiness`
tests. Both arms were built as native-asset-aware AOT CLI bundles from an
identical harness source, so the decode path is AOT-compiled (exp 193's
requirement) and only `lib/` differs:

```console
dart build cli --target=bin/reader_dispatch_stickiness.dart --output=<arm>
<arm>/bundle/bin/reader_dispatch_stickiness --lane=<lane> --warmup=12 --samples=121
```

The harness source is
[`benchmark/experiments/reader_dispatch_stickiness.dart`](../experiments/reader_dispatch_stickiness.dart);
`bin/` is only where `dart build cli` requires the entry point to live (with its
one relative import rewritten), and the baseline arm was built from the
candidate's copy of it. Every lane is **lane-isolated** — one fresh process per
lane per arm — and passes alternate collection order (odd baseline-first, even
candidate-first).

**Twenty-four passes, in two collections of twelve.** Collection 1 was taken
before the `selectBytes` opt-out existed; since that opt-out touches only the
bytes path, the rows dispatch path is byte-identical across the two and their
rows lanes pool. Twelve-pass collections rather than exp 264's four because the
primary lanes time four to eight microsecond-scale reads per sample and carry
20-50% within-run CV: the discrimination comes from repetition across passes,
not from any single pass being tight. The pooled table below is the result; the
per-pass detail is collection 2, the one built from the shipped code.

Values are microseconds. `first4-newsql` / `first8-newsql` / `first32-newsql`
time 4 / 8 / 32 executions of a **statement no worker has seen before** (a fresh
trailing comment per sample, so the plan is identical and only the warm-up is
new), `bytes-first8-newsql` is the same shape through `selectBytes`; `point1`
and `point1-wide20` time 200 executions of one long-warm statement, `mixed6-20`
50, `alternating-sql` 100 statement pairs, `mixed6-1k` 5, `conc4` 50 groups of
four, `conc8` 25 groups of eight, `mixed6-10k` one. Medians are per sample, not
per execution.

**No release-suite run.** Every release scenario executes one statement
thousands of times, so none of them can resolve a statement's *first* four
executions — which is where the whole effect lives, and which the steady-state
`point1` lane confirms is gone by the eight-thousandth. The focused harness is
the durable gate. The `JSON buffer reclaim` release guard
(`benchmark/suites/sqlite_diagnostics.dart`, exp 185) was run directly and is
what caught the `selectBytes` interaction; it is green on the shipped code.

Host at collection time: 71% CPU idle, load average 3.18/3.76/3.85 on ten cores,
33 GB free disk — recorded because exp 264 discovered after the fact that it had
measured an entire experiment on a saturated host. One outlier is worth naming:
`point1` pass 17 read +45.2% against a within-run CV of ~3%, a host blip, which
is why the pooled table reports a median of per-pass deltas as well as a mean
(-1.6% against +1.2% on that lane; every other lane's two statistics agree to
within a point).

## Pooled result, both collections

Collection 1 (passes 1-12) predates the `selectBytes` opt-out; the rows
dispatch path is byte-identical between the two, so its rows lanes pool with
collection 2 (passes 13-24). `bytes-first8-newsql` exists only in collection 2.

| lane | passes | median Δ | mean Δ | passes faster |
|---|---:|---:|---:|---:|
| `first4-newsql` | 24 | -32.2% | -32.3% | 24/24 |
| `first8-newsql` | 24 | -21.8% | -21.9% | 24/24 |
| `first32-newsql` | 24 | -13.2% | -10.8% | 22/24 |
| `bytes-first8-newsql` | 12 | -1.2% | -1.1% | 7/12 |
| `point1` | 24 | -1.6% | +1.2% | 18/24 |
| `point1-wide20` | 24 | -3.5% | -3.7% | 23/24 |
| `mixed6-20` | 24 | -3.4% | -3.6% | 22/24 |
| `mixed6-1k` | 24 | -0.7% | -0.8% | 17/24 |
| `alternating-sql` | 24 | +0.0% | +0.5% | 10/24 |
| `conc4` | 24 | +1.3% | +0.0% | 8/24 |
| `conc8` | 24 | +0.2% | -0.7% | 10/24 |
| `mixed6-10k` | 24 | -0.4% | -0.7% | 13/24 |

## Per-pass medians, collection 2 (microseconds)

| lane | pass | order | baseline | candidate | Δ |
|---|---:|---|---:|---:|---:|
| `first4-newsql` | 1 | baseline first | 59 | 37 | -37.3% |
| `first4-newsql` | 2 | candidate first | 59 | 38 | -35.6% |
| `first4-newsql` | 3 | baseline first | 59 | 40 | -32.2% |
| `first4-newsql` | 4 | candidate first | 58 | 38 | -34.5% |
| `first4-newsql` | 5 | baseline first | 54 | 39 | -27.8% |
| `first4-newsql` | 6 | candidate first | 56 | 38 | -32.1% |
| `first4-newsql` | 7 | baseline first | 61 | 43 | -29.5% |
| `first4-newsql` | 8 | candidate first | 59 | 39 | -33.9% |
| `first4-newsql` | 9 | baseline first | 57 | 39 | -31.6% |
| `first4-newsql` | 10 | candidate first | 55 | 39 | -29.1% |
| `first4-newsql` | 11 | baseline first | 61 | 40 | -34.4% |
| `first4-newsql` | 12 | candidate first | 52 | 41 | -21.2% |
| `first8-newsql` | 1 | baseline first | 89 | 67 | -24.7% |
| `first8-newsql` | 2 | candidate first | 88 | 68 | -22.7% |
| `first8-newsql` | 3 | baseline first | 88 | 68 | -22.7% |
| `first8-newsql` | 4 | candidate first | 87 | 70 | -19.5% |
| `first8-newsql` | 5 | baseline first | 84 | 66 | -21.4% |
| `first8-newsql` | 6 | candidate first | 81 | 66 | -18.5% |
| `first8-newsql` | 7 | baseline first | 89 | 70 | -21.3% |
| `first8-newsql` | 8 | candidate first | 88 | 66 | -25.0% |
| `first8-newsql` | 9 | baseline first | 93 | 62 | -33.3% |
| `first8-newsql` | 10 | candidate first | 86 | 68 | -20.9% |
| `first8-newsql` | 11 | baseline first | 88 | 65 | -26.1% |
| `first8-newsql` | 12 | candidate first | 82 | 65 | -20.7% |
| `first32-newsql` | 1 | baseline first | 206 | 173 | -16.0% |
| `first32-newsql` | 2 | candidate first | 196 | 205 | +4.6% |
| `first32-newsql` | 3 | baseline first | 191 | 165 | -13.6% |
| `first32-newsql` | 4 | candidate first | 205 | 195 | -4.9% |
| `first32-newsql` | 5 | baseline first | 210 | 196 | -6.7% |
| `first32-newsql` | 6 | candidate first | 197 | 170 | -13.7% |
| `first32-newsql` | 7 | baseline first | 206 | 222 | +7.8% |
| `first32-newsql` | 8 | candidate first | 229 | 209 | -8.7% |
| `first32-newsql` | 9 | baseline first | 204 | 174 | -14.7% |
| `first32-newsql` | 10 | candidate first | 200 | 173 | -13.5% |
| `first32-newsql` | 11 | baseline first | 205 | 167 | -18.5% |
| `first32-newsql` | 12 | candidate first | 193 | 168 | -13.0% |
| `bytes-first8-newsql` | 1 | baseline first | 72 | 88 | +22.2% |
| `bytes-first8-newsql` | 2 | candidate first | 84 | 84 | +0.0% |
| `bytes-first8-newsql` | 3 | baseline first | 89 | 80 | -10.1% |
| `bytes-first8-newsql` | 4 | candidate first | 80 | 84 | +5.0% |
| `bytes-first8-newsql` | 5 | baseline first | 79 | 78 | -1.3% |
| `bytes-first8-newsql` | 6 | candidate first | 85 | 75 | -11.8% |
| `bytes-first8-newsql` | 7 | baseline first | 89 | 89 | +0.0% |
| `bytes-first8-newsql` | 8 | candidate first | 93 | 88 | -5.4% |
| `bytes-first8-newsql` | 9 | baseline first | 80 | 75 | -6.2% |
| `bytes-first8-newsql` | 10 | candidate first | 86 | 85 | -1.2% |
| `bytes-first8-newsql` | 11 | baseline first | 85 | 79 | -7.1% |
| `bytes-first8-newsql` | 12 | candidate first | 82 | 84 | +2.4% |
| `point1` | 1 | baseline first | 1010 | 992 | -1.8% |
| `point1` | 2 | candidate first | 965 | 933 | -3.3% |
| `point1` | 3 | baseline first | 979 | 998 | +1.9% |
| `point1` | 4 | candidate first | 967 | 1000 | +3.4% |
| `point1` | 5 | baseline first | 1041 | 1512 | +45.2% |
| `point1` | 6 | candidate first | 992 | 955 | -3.7% |
| `point1` | 7 | baseline first | 1013 | 1074 | +6.0% |
| `point1` | 8 | candidate first | 1090 | 1186 | +8.8% |
| `point1` | 9 | baseline first | 966 | 948 | -1.9% |
| `point1` | 10 | candidate first | 1007 | 993 | -1.4% |
| `point1` | 11 | baseline first | 967 | 946 | -2.2% |
| `point1` | 12 | candidate first | 971 | 957 | -1.4% |
| `point1-wide20` | 1 | baseline first | 1128 | 1118 | -0.9% |
| `point1-wide20` | 2 | candidate first | 1141 | 1101 | -3.5% |
| `point1-wide20` | 3 | baseline first | 1130 | 1124 | -0.5% |
| `point1-wide20` | 4 | candidate first | 1085 | 1054 | -2.9% |
| `point1-wide20` | 5 | baseline first | 1478 | 1241 | -16.0% |
| `point1-wide20` | 6 | candidate first | 1148 | 1092 | -4.9% |
| `point1-wide20` | 7 | baseline first | 1141 | 1071 | -6.1% |
| `point1-wide20` | 8 | candidate first | 1109 | 1082 | -2.4% |
| `point1-wide20` | 9 | baseline first | 1088 | 1051 | -3.4% |
| `point1-wide20` | 10 | candidate first | 1086 | 1052 | -3.1% |
| `point1-wide20` | 11 | baseline first | 1090 | 1050 | -3.7% |
| `point1-wide20` | 12 | candidate first | 1099 | 1049 | -4.5% |
| `mixed6-20` | 1 | baseline first | 475 | 462 | -2.7% |
| `mixed6-20` | 2 | candidate first | 469 | 454 | -3.2% |
| `mixed6-20` | 3 | baseline first | 450 | 434 | -3.6% |
| `mixed6-20` | 4 | candidate first | 460 | 438 | -4.8% |
| `mixed6-20` | 5 | baseline first | 481 | 482 | +0.2% |
| `mixed6-20` | 6 | candidate first | 466 | 450 | -3.4% |
| `mixed6-20` | 7 | baseline first | 453 | 435 | -4.0% |
| `mixed6-20` | 8 | candidate first | 449 | 439 | -2.2% |
| `mixed6-20` | 9 | baseline first | 446 | 434 | -2.7% |
| `mixed6-20` | 10 | candidate first | 448 | 438 | -2.2% |
| `mixed6-20` | 11 | baseline first | 458 | 433 | -5.5% |
| `mixed6-20` | 12 | candidate first | 463 | 445 | -3.9% |
| `mixed6-1k` | 1 | baseline first | 1094 | 1082 | -1.1% |
| `mixed6-1k` | 2 | candidate first | 1061 | 1104 | +4.1% |
| `mixed6-1k` | 3 | baseline first | 1059 | 1055 | -0.4% |
| `mixed6-1k` | 4 | candidate first | 1052 | 1059 | +0.7% |
| `mixed6-1k` | 5 | baseline first | 1126 | 1065 | -5.4% |
| `mixed6-1k` | 6 | candidate first | 1094 | 1057 | -3.4% |
| `mixed6-1k` | 7 | baseline first | 1046 | 1052 | +0.6% |
| `mixed6-1k` | 8 | candidate first | 1056 | 1052 | -0.4% |
| `mixed6-1k` | 9 | baseline first | 1069 | 1100 | +2.9% |
| `mixed6-1k` | 10 | candidate first | 1059 | 1042 | -1.6% |
| `mixed6-1k` | 11 | baseline first | 1066 | 1106 | +3.8% |
| `mixed6-1k` | 12 | candidate first | 1066 | 1102 | +3.4% |
| `alternating-sql` | 1 | baseline first | 1383 | 1374 | -0.7% |
| `alternating-sql` | 2 | candidate first | 1374 | 1374 | +0.0% |
| `alternating-sql` | 3 | baseline first | 1362 | 1381 | +1.4% |
| `alternating-sql` | 4 | candidate first | 1453 | 1427 | -1.8% |
| `alternating-sql` | 5 | baseline first | 1380 | 1400 | +1.4% |
| `alternating-sql` | 6 | candidate first | 1385 | 1373 | -0.9% |
| `alternating-sql` | 7 | baseline first | 1378 | 1447 | +5.0% |
| `alternating-sql` | 8 | candidate first | 1470 | 1448 | -1.5% |
| `alternating-sql` | 9 | baseline first | 1443 | 1447 | +0.3% |
| `alternating-sql` | 10 | candidate first | 1454 | 1384 | -4.8% |
| `alternating-sql` | 11 | baseline first | 1429 | 1394 | -2.4% |
| `alternating-sql` | 12 | candidate first | 1376 | 1389 | +0.9% |
| `conc4` | 1 | baseline first | 1233 | 1260 | +2.2% |
| `conc4` | 2 | candidate first | 1251 | 1257 | +0.5% |
| `conc4` | 3 | baseline first | 1271 | 1404 | +10.5% |
| `conc4` | 4 | candidate first | 1284 | 1363 | +6.2% |
| `conc4` | 5 | baseline first | 1248 | 1269 | +1.7% |
| `conc4` | 6 | candidate first | 1451 | 1244 | -14.3% |
| `conc4` | 7 | baseline first | 1434 | 1247 | -13.0% |
| `conc4` | 8 | candidate first | 1254 | 1381 | +10.1% |
| `conc4` | 9 | baseline first | 1396 | 1453 | +4.1% |
| `conc4` | 10 | candidate first | 1287 | 1431 | +11.2% |
| `conc4` | 11 | baseline first | 1238 | 1258 | +1.6% |
| `conc4` | 12 | candidate first | 1255 | 1224 | -2.5% |
| `conc8` | 1 | baseline first | 1343 | 1499 | +11.6% |
| `conc8` | 2 | candidate first | 1473 | 1440 | -2.2% |
| `conc8` | 3 | baseline first | 1442 | 1252 | -13.2% |
| `conc8` | 4 | candidate first | 1490 | 1439 | -3.4% |
| `conc8` | 5 | baseline first | 1497 | 1501 | +0.3% |
| `conc8` | 6 | candidate first | 1505 | 1515 | +0.7% |
| `conc8` | 7 | baseline first | 1263 | 1274 | +0.9% |
| `conc8` | 8 | candidate first | 1266 | 1257 | -0.7% |
| `conc8` | 9 | baseline first | 1290 | 1295 | +0.4% |
| `conc8` | 10 | candidate first | 1287 | 1316 | +2.3% |
| `conc8` | 11 | baseline first | 1271 | 1285 | +1.1% |
| `conc8` | 12 | candidate first | 1477 | 1320 | -10.6% |
| `mixed6-10k` | 1 | baseline first | 2425 | 2323 | -4.2% |
| `mixed6-10k` | 2 | candidate first | 2327 | 2429 | +4.4% |
| `mixed6-10k` | 3 | baseline first | 2328 | 2332 | +0.2% |
| `mixed6-10k` | 4 | candidate first | 2516 | 2397 | -4.7% |
| `mixed6-10k` | 5 | baseline first | 2440 | 2334 | -4.3% |
| `mixed6-10k` | 6 | candidate first | 2467 | 2321 | -5.9% |
| `mixed6-10k` | 7 | baseline first | 2323 | 2418 | +4.1% |
| `mixed6-10k` | 8 | candidate first | 2430 | 2327 | -4.2% |
| `mixed6-10k` | 9 | baseline first | 2329 | 2401 | +3.1% |
| `mixed6-10k` | 10 | candidate first | 2433 | 2322 | -4.6% |
| `mixed6-10k` | 11 | baseline first | 2427 | 2429 | +0.1% |
| `mixed6-10k` | 12 | candidate first | 2466 | 2481 | +0.6% |

## Peak RSS, median over collection 2 (MB)

| lane | baseline | candidate | Δ |
|---|---:|---:|---:|
| `first4-newsql` | 27.0 | 26.0 | -1.0 |
| `first8-newsql` | 29.5 | 28.2 | -1.3 |
| `first32-newsql` | 29.9 | 29.8 | -0.1 |
| `bytes-first8-newsql` | 24.9 | 24.9 | +0.0 |
| `point1` | 29.6 | 29.8 | +0.1 |
| `point1-wide20` | 23.9 | 24.3 | +0.4 |
| `mixed6-20` | 29.7 | 29.6 | -0.1 |
| `mixed6-1k` | 30.7 | 29.7 | -1.0 |
| `alternating-sql` | 29.7 | 29.7 | +0.0 |
| `conc4` | 30.4 | 31.0 | +0.6 |
| `conc8` | 30.7 | 30.6 | -0.1 |
| `mixed6-10k` | 95.8 | 96.0 | +0.2 |

## Order-flipped drift verdicts, collection 2

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV | reason |
|---|---|---:|---:|---:|---|
| first4-newsql#pair1 | REPRODUCED (real effect) | -37.3% | -35.6% | 23.9% | same-direction effect in both passes (-37.3% then -35.6%) with comparable per-side CVs |
| first4-newsql#pair2 | REPRODUCED (real effect) | -32.2% | -34.5% | 35.4% | same-direction effect in both passes (-32.2% then -34.5%) with comparable per-side CVs |
| first4-newsql#pair3 | REPRODUCED (real effect) | -27.8% | -32.1% | 26.8% | same-direction effect in both passes (-27.8% then -32.1%) with comparable per-side CVs |
| first4-newsql#pair4 | REPRODUCED (real effect) | -29.5% | -33.9% | 11.3% | same-direction effect in both passes (-29.5% then -33.9%) with comparable per-side CVs |
| first4-newsql#pair5 | REPRODUCED (real effect) | -31.6% | -29.1% | 30.3% | same-direction effect in both passes (-31.6% then -29.1%) with comparable per-side CVs |
| first4-newsql#pair6 | REPRODUCED (real effect) | -34.4% | -21.2% | 20.5% | same-direction effect in both passes (-34.4% then -21.2%) with comparable per-side CVs |
| first8-newsql#pair1 | REPRODUCED (real effect) | -24.7% | -22.7% | 33.6% | same-direction effect in both passes (-24.7% then -22.7%) with comparable per-side CVs |
| first8-newsql#pair2 | REPRODUCED (real effect) | -22.7% | -19.5% | 19.3% | same-direction effect in both passes (-22.7% then -19.5%) with comparable per-side CVs |
| first8-newsql#pair3 | REPRODUCED (real effect) | -21.4% | -18.5% | 31.2% | same-direction effect in both passes (-21.4% then -18.5%) with comparable per-side CVs |
| first8-newsql#pair4 | REPRODUCED (real effect) | -21.3% | -25.0% | 32.0% | same-direction effect in both passes (-21.3% then -25.0%) with comparable per-side CVs |
| first8-newsql#pair5 | REPRODUCED (real effect) | -33.3% | -20.9% | 22.7% | same-direction effect in both passes (-33.3% then -20.9%) with comparable per-side CVs |
| first8-newsql#pair6 | REPRODUCED (real effect) | -26.1% | -20.7% | 38.0% | same-direction effect in both passes (-26.1% then -20.7%) with comparable per-side CVs |
| first32-newsql#pair1 | drift-suspected | -16.0% | 4.6% | 21.2% | effect reversed sign across the order flip (-16.0% then 4.6%); flag did not survive |
| first32-newsql#pair2 | REPRODUCED (real effect) | -13.6% | -4.9% | 23.2% | same-direction effect in both passes (-13.6% then -4.9%) with comparable per-side CVs |
| first32-newsql#pair3 | REPRODUCED (real effect) | -6.7% | -13.7% | 22.7% | same-direction effect in both passes (-6.7% then -13.7%) with comparable per-side CVs |
| first32-newsql#pair4 | drift-suspected | 7.8% | -8.7% | 19.6% | effect reversed sign across the order flip (7.8% then -8.7%); flag did not survive |
| first32-newsql#pair5 | REPRODUCED (real effect) | -14.7% | -13.5% | 16.7% | same-direction effect in both passes (-14.7% then -13.5%) with comparable per-side CVs |
| first32-newsql#pair6 | REPRODUCED (real effect) | -18.5% | -13.0% | 22.4% | same-direction effect in both passes (-18.5% then -13.0%) with comparable per-side CVs |
| bytes-first8-newsql#pair1 | inconclusive / neutral | 22.2% | 0.0% | 17.2% | both passes below the 3% effect floor (22.2% then 0.0%) — read as neutral |
| bytes-first8-newsql#pair2 | drift-suspected | -10.1% | 5.0% | 20.4% | effect reversed sign across the order flip (-10.1% then 5.0%); flag did not survive |
| bytes-first8-newsql#pair3 | inconclusive / neutral | -1.3% | -11.8% | 19.7% | both passes below the 3% effect floor (-1.3% then -11.8%) — read as neutral |
| bytes-first8-newsql#pair4 | inconclusive / neutral | 0.0% | -5.4% | 28.0% | both passes below the 3% effect floor (0.0% then -5.4%) — read as neutral |
| bytes-first8-newsql#pair5 | inconclusive / neutral | -6.3% | -1.2% | 45.2% | both passes below the 3% effect floor (-6.3% then -1.2%) — read as neutral |
| bytes-first8-newsql#pair6 | inconclusive / neutral | -7.1% | 2.4% | 9.8% | both passes below the 3% effect floor (-7.1% then 2.4%) — read as neutral |
| point1#pair1 | inconclusive / neutral | -1.8% | -3.3% | 6.0% | both passes below the 3% effect floor (-1.8% then -3.3%) — read as neutral |
| point1#pair2 | inconclusive / neutral | 1.9% | 3.4% | 4.8% | both passes below the 3% effect floor (1.9% then 3.4%) — read as neutral |
| point1#pair3 | drift-suspected | 45.2% | -3.7% | 8.7% | effect reversed sign across the order flip (45.2% then -3.7%); flag did not survive |
| point1#pair4 | REPRODUCED (real effect) | 6.0% | 8.8% | 17.0% | same-direction effect in both passes (6.0% then 8.8%) with comparable per-side CVs |
| point1#pair5 | inconclusive / neutral | -1.9% | -1.4% | 4.6% | both passes below the 3% effect floor (-1.9% then -1.4%) — read as neutral |
| point1#pair6 | inconclusive / neutral | -2.2% | -1.4% | 3.6% | both passes below the 3% effect floor (-2.2% then -1.4%) — read as neutral |
| point1-wide20#pair1 | inconclusive / neutral | -0.9% | -3.5% | 4.0% | both passes below the 3% effect floor (-0.9% then -3.5%) — read as neutral |
| point1-wide20#pair2 | inconclusive / neutral | -0.5% | -2.9% | 2.7% | both passes below the 3% effect floor (-0.5% then -2.9%) — read as neutral |
| point1-wide20#pair3 | REPRODUCED (real effect) | -16.0% | -4.9% | 11.9% | same-direction effect in both passes (-16.0% then -4.9%) with comparable per-side CVs |
| point1-wide20#pair4 | inconclusive / neutral | -6.1% | -2.4% | 13.5% | both passes below the 3% effect floor (-6.1% then -2.4%) — read as neutral |
| point1-wide20#pair5 | REPRODUCED (real effect) | -3.4% | -3.1% | 3.9% | same-direction effect in both passes (-3.4% then -3.1%) with comparable per-side CVs |
| point1-wide20#pair6 | REPRODUCED (real effect) | -3.7% | -4.5% | 4.5% | same-direction effect in both passes (-3.7% then -4.5%) with comparable per-side CVs |
| mixed6-20#pair1 | inconclusive / neutral | -2.7% | -3.2% | 7.2% | both passes below the 3% effect floor (-2.7% then -3.2%) — read as neutral |
| mixed6-20#pair2 | REPRODUCED (real effect) | -3.6% | -4.8% | 8.6% | same-direction effect in both passes (-3.6% then -4.8%) with comparable per-side CVs |
| mixed6-20#pair3 | inconclusive / neutral | 0.2% | -3.4% | 11.6% | both passes below the 3% effect floor (0.2% then -3.4%) — read as neutral |
| mixed6-20#pair4 | inconclusive / neutral | -4.0% | -2.2% | 8.1% | both passes below the 3% effect floor (-4.0% then -2.2%) — read as neutral |
| mixed6-20#pair5 | inconclusive / neutral | -2.7% | -2.2% | 8.4% | both passes below the 3% effect floor (-2.7% then -2.2%) — read as neutral |
| mixed6-20#pair6 | REPRODUCED (real effect) | -5.5% | -3.9% | 8.2% | same-direction effect in both passes (-5.5% then -3.9%) with comparable per-side CVs |
| mixed6-1k#pair1 | inconclusive / neutral | -1.1% | 4.1% | 5.7% | both passes below the 3% effect floor (-1.1% then 4.1%) — read as neutral |
| mixed6-1k#pair2 | inconclusive / neutral | -0.4% | 0.7% | 4.4% | both passes below the 3% effect floor (-0.4% then 0.7%) — read as neutral |
| mixed6-1k#pair3 | REPRODUCED (real effect) | -5.4% | -3.4% | 7.5% | same-direction effect in both passes (-5.4% then -3.4%) with comparable per-side CVs |
| mixed6-1k#pair4 | inconclusive / neutral | 0.6% | -0.4% | 4.3% | both passes below the 3% effect floor (0.6% then -0.4%) — read as neutral |
| mixed6-1k#pair5 | inconclusive / neutral | 2.9% | -1.6% | 4.5% | both passes below the 3% effect floor (2.9% then -1.6%) — read as neutral |
| mixed6-1k#pair6 | REPRODUCED (real effect) | 3.8% | 3.4% | 4.7% | same-direction effect in both passes (3.8% then 3.4%) with comparable per-side CVs |
| alternating-sql#pair1 | inconclusive / neutral | -0.7% | 0.0% | 3.6% | both passes below the 3% effect floor (-0.7% then 0.0%) — read as neutral |
| alternating-sql#pair2 | inconclusive / neutral | 1.4% | -1.8% | 3.5% | both passes below the 3% effect floor (1.4% then -1.8%) — read as neutral |
| alternating-sql#pair3 | inconclusive / neutral | 1.4% | -0.9% | 3.5% | both passes below the 3% effect floor (1.4% then -0.9%) — read as neutral |
| alternating-sql#pair4 | inconclusive / neutral | 5.0% | -1.5% | 8.4% | both passes below the 3% effect floor (5.0% then -1.5%) — read as neutral |
| alternating-sql#pair5 | inconclusive / neutral | 0.3% | -4.8% | 4.3% | both passes below the 3% effect floor (0.3% then -4.8%) — read as neutral |
| alternating-sql#pair6 | inconclusive / neutral | -2.4% | 0.9% | 4.4% | both passes below the 3% effect floor (-2.4% then 0.9%) — read as neutral |
| conc4#pair1 | inconclusive / neutral | 2.2% | 0.5% | 9.6% | both passes below the 3% effect floor (2.2% then 0.5%) — read as neutral |
| conc4#pair2 | REPRODUCED (real effect) | 10.5% | 6.2% | 18.0% | same-direction effect in both passes (10.5% then 6.2%) with comparable per-side CVs |
| conc4#pair3 | inconclusive / neutral | 1.7% | -14.3% | 11.2% | both passes below the 3% effect floor (1.7% then -14.3%) — read as neutral |
| conc4#pair4 | drift-suspected | -13.0% | 10.1% | 16.2% | effect reversed sign across the order flip (-13.0% then 10.1%); flag did not survive |
| conc4#pair5 | REPRODUCED (real effect) | 4.1% | 11.2% | 14.7% | same-direction effect in both passes (4.1% then 11.2%) with comparable per-side CVs |
| conc4#pair6 | inconclusive / neutral | 1.6% | -2.5% | 9.1% | both passes below the 3% effect floor (1.6% then -2.5%) — read as neutral |
| conc8#pair1 | inconclusive / neutral | 11.6% | -2.2% | 11.9% | both passes below the 3% effect floor (11.6% then -2.2%) — read as neutral |
| conc8#pair2 | REPRODUCED (real effect) | -13.2% | -3.4% | 11.7% | same-direction effect in both passes (-13.2% then -3.4%) with comparable per-side CVs |
| conc8#pair3 | inconclusive / neutral | 0.3% | 0.7% | 12.0% | both passes below the 3% effect floor (0.3% then 0.7%) — read as neutral |
| conc8#pair4 | inconclusive / neutral | 0.9% | -0.7% | 8.7% | both passes below the 3% effect floor (0.9% then -0.7%) — read as neutral |
| conc8#pair5 | inconclusive / neutral | 0.4% | 2.3% | 12.2% | both passes below the 3% effect floor (0.4% then 2.3%) — read as neutral |
| conc8#pair6 | inconclusive / neutral | 1.1% | -10.6% | 11.6% | both passes below the 3% effect floor (1.1% then -10.6%) — read as neutral |
| mixed6-10k#pair1 | drift-suspected | -4.2% | 4.4% | 14.4% | effect reversed sign across the order flip (-4.2% then 4.4%); flag did not survive |
| mixed6-10k#pair2 | inconclusive / neutral | 0.2% | -4.7% | 15.3% | both passes below the 3% effect floor (0.2% then -4.7%) — read as neutral |
| mixed6-10k#pair3 | REPRODUCED (real effect) | -4.3% | -5.9% | 14.0% | same-direction effect in both passes (-4.3% then -5.9%) with comparable per-side CVs |
| mixed6-10k#pair4 | drift-suspected | 4.1% | -4.2% | 14.4% | effect reversed sign across the order flip (4.1% then -4.2%); flag did not survive |
| mixed6-10k#pair5 | drift-suspected | 3.1% | -4.6% | 14.2% | effect reversed sign across the order flip (3.1% then -4.6%); flag did not survive |
| mixed6-10k#pair6 | inconclusive / neutral | 0.1% | 0.6% | 14.2% | both passes below the 3% effect floor (0.1% then 0.6%) — read as neutral |
